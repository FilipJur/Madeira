import SwiftUI
import UIKit

/// The widget layer of a library session, hosted by TouchControlsOverlay.controls(_:session:)
/// in place of Madeira's own buttons (docs/fork/TOUCH-PORT.md "Host contract", R3 §6). It
/// takes the role StreamView's top layer view has in VoidLink: `VLTouchContainer` holds the
/// `OnScreenWidgetView`s, the editor and the profile pickers are presented over it by
/// `VLTouchHost`, and it is rebuilt when its size changes or one of them closes.
struct VLTouchLayer: UIViewRepresentable {
    var screen: CGSize
    var opacity: Double

    func makeUIView(context: Context) -> VLTouchContainer { VLTouchContainer() }

    func updateUIView(_ view: VLTouchContainer, context: Context) { view.alpha = opacity }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: VLTouchContainer, context: Context) -> CGSize? { screen }

    static func dismantleUIView(_ view: VLTouchContainer, coordinator: ()) { view.teardown() }

    /// ControlsWindow.hitTest: the widget under `point` (a point in `window`), nil for empty
    /// space, which belongs to the game underneath (mouse-look between the widgets).
    static func hit(_ point: CGPoint, with event: UIEvent?, in window: UIWindow) -> UIView? {
        guard let container = VLTouchContainer.current, container.window === window else { return nil }
        return container.hitTest(container.convert(point, from: window), with: event)
    }

    /// Writes what the widgets changed on their own (a dragged movable widget, folder states)
    /// into the selected profile.
    static func flush() { VLTouchContainer.current?.persistChanges() }

    /// An editor or picker is about to open: save, remove the widgets.
    static func suspend() { VLTouchContainer.current?.suspend() }

    /// The editor or picker closed: build the widgets again from the selected profile.
    static func resume() { VLTouchContainer.current?.resume() }
}

final class VLTouchContainer: UIView {
    /// The live container; the overlay hosts one.
    static weak var current: VLTouchContainer?

    // VLTouch: StreamConfiguration is a header-only stub (Compat), so there is no class to
    // instantiate; both initialisers take nil and keep their defaults.
    private lazy var controllerSupport = ControllerSupport(config: nil)
    private var onScreenControls: OnScreenControls?
    private var hasLegacyWidget = false
    private var builtSize = CGSize.zero
    private var builtProfileName: String?
    private var suspended = false
    private var rebuildPending = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        // Built while an editor or picker is open (the session menu closed to open one): the
        // widget state is theirs until they close, then `resume()` builds it.
        suspended = VLTouchHost.modalOpen
        VLTouchContainer.current = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != builtSize { scheduleRebuild() }
    }

    /// The container is the widgets' canvas, not a hit target of its own: only a widget (or a
    /// legacy button layer) takes a touch, the rest of the screen is the game's.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !suspended, !isHidden, alpha > 0.01, bounds.contains(point) else { return nil }
        for case let widget as OnScreenWidgetView in subviews.reversed() {
            if let hit = widget.hitTest(convert(point, to: widget), with: event) { return hit }
        }
        return legacyLayerHit(point) ? self : nil
    }

    // MARK: Legacy widgets (VoidLink's drawn controller layers)

    private func legacyLayerHit(_ point: CGPoint) -> Bool {
        guard hasLegacyWidget, let pool = onScreenControls?.oscButtonLayerPool,
              let hit = layer.hitTest(layer.convert(point, to: layer.superlayer)), hit !== layer else { return false }
        var candidate: CALayer? = hit
        while let l = candidate, l !== layer {
            if pool.contains(l) { return true }
            candidate = l.superlayer
        }
        return false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        _ = onScreenControls?.handleTouchDownEvent(touches as Set<AnyHashable>)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        _ = onScreenControls?.handleTouchMovedEvent(touches as Set<AnyHashable>)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        _ = onScreenControls?.handleTouchUpEvent(touches as Set<AnyHashable>)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        _ = onScreenControls?.handleTouchUpEvent(touches as Set<AnyHashable>)
    }

    // MARK: Lifecycle

    private func scheduleRebuild() {
        guard !suspended, !rebuildPending else { return }
        rebuildPending = true
        // VoidLink's reloadGameProfile runs on the next main-queue turn, never inside layout.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rebuildPending = false
            self.rebuild()
        }
    }

    func suspend() {
        persistChanges()
        clearWidgets()
        suspended = true
        builtSize = .zero
    }

    func resume() {
        suspended = false
        // Not persisted first: what the editor discarded must not be written back.
        rebuild(persistFirst: false)
    }

    /// SwiftUI dropped the layer (the menu opened, the session ended): save and let go.
    func teardown() {
        // A newer container owns the shared widget state by now: leave it alone.
        guard VLTouchContainer.current === self else {
            for case let widget as OnScreenWidgetView in subviews { widget.removeFromSuperview() }
            suspended = true
            return
        }
        // Suspended (an editor or picker is open): the widgets are gone and the state is theirs.
        if !suspended {
            persistChanges()
            clearWidgets()
        }
        suspended = true
        VLTouchContainer.current = nil
    }

    private func clearWidgets() {
        OnScreenWidgetView.isTweakingHighlight = false
        OnScreenWidgetView.clearMappings()
        for case let widget as OnScreenWidgetView in subviews { widget.removeFromSuperview() }
        if let pool = onScreenControls?.oscButtonLayerPool {
            for case let l as CALayer in pool { l.removeFromSuperlayer() }
            pool.removeAllObjects()
        }
        onScreenControls?.setLevel(.off)
        onScreenControls = nil
        hasLegacyWidget = false
        // A widget that was removed while held must not keep the pad or a key down. The legacy
        // pad state goes first, or the next updateFinished would republish the held bits.
        controllerSupport?.resetState()
        VLSink.releaseAll()
    }

    // MARK: Building the widgets (StreamView.m reloadGameProfile:reloadWidgets:)

    private func widgetSizeReference(_ manager: OSCProfilesManager) -> WidgetSizeReference {
        switch manager.widgetSizeTransition {
        case .keepWidgetSize: return .longSide                                    // StreamView.m:894
        case .transitionWithOrientation: return bounds.width > bounds.height ? .longSide : .shortSide   // :895
        }
    }

    private func rebuild(persistFirst: Bool = true) {
        // StreamView.m:985 -- never while the editor owns the widget state.
        guard !suspended, !OnScreenWidgetView.editMode, bounds.width > 0, bounds.height > 0 else { return }
        if persistFirst { persistChanges() }   // positions are normalised against the size they were laid out for
        clearWidgets()
        builtSize = bounds.size

        // StreamView.m:957 -- the profiles manager wants the container's bounds.
        VLProfiles.prepare(bounds: bounds)
        let manager = OSCProfilesManager.sharedManager(bounds)
        let profile = manager.getSelectedProfile()
        builtProfileName = profile.name

        // StreamView.m:858 / :866 -- OnScreenControls on this view; custom level.
        let osc = OnScreenControls(view: self, controllerSup: controllerSupport, streamConfig: nil)
        osc?.setLevel(.custom)
        onScreenControls = osc

        // StreamView.m:966-982
        let motionHandler = MotionHandler.shared(profile: profile)
        OnScreenWidgetView.buttonVisualFeedbackEnabled = true   // upstream: a stream setting Madeira has no counterpart for
        OnScreenWidgetView.gamepadOverlayFLag = profile.gamepadOverlayEnabled
        // StreamView.m:989-990
        StreamFrameViewController.sharedInstance()?.touchDisabled = false
        StreamFrameViewController.sharedInstance()?.singleTouchDisabled = false

        var sequenceGenerated = false
        var hasMovableWidget = false
        let sizeReference = widgetSizeReference(manager)

        // StreamView.m:999-1097
        for i in 0..<profile.buttonStatesEncoded.count {
            guard let encoded = profile.buttonStatesEncoded[i] as? Data else { continue }
            let buttonState = manager.unarchiveButtonStateEncoded(encoded)
            if buttonState.widgetType == 1 {   // CustomOnScreenWidget
                guard let widgetView = OnScreenWidgetView.widget(cmdString: buttonState.name,
                                                                 buttonLabel: buttonState.alias,
                                                                 shape: buttonState.widgetShape,
                                                                 profile: profile) else { continue }

                widgetView.functionalWidgetDelegate = VLTouchHost.shared
                widgetView.motionHandler = motionHandler

                widgetView.sequence = buttonState.sequence == -1 ? Int16(i) : buttonState.sequence
                if !sequenceGenerated { sequenceGenerated = buttonState.sequence == -1 }
                if !hasMovableWidget { hasMovableWidget = buttonState.buttonMode == UInt8(ButtonMode.movable.rawValue) }
                OnScreenWidgetView.set(widget: widgetView, for: widgetView.sequence)
                widgetView.sequenceSet = buttonState.sequenceSet as? Set<Int16> ?? Set()
                widgetView.parentSequence = buttonState.parentSequence
                widgetView.autoDockIdleDuration = TimeInterval(buttonState.autoDockTimer)
                widgetView.storedAutoDockIdleDuration = widgetView.autoDockIdleDuration
                widgetView.autoDockSettledAlpha = CGFloat(buttonState.dockedAlpha)
                widgetView.folded = buttonState.folded
                widgetView.persistedFolded = buttonState.folded
                widgetView.revealMode = RevealMode(rawValue: Int(buttonState.revealMode)) ?? .coexist
                widgetView.bulkMoveEnabled = buttonState.bulkMoveEnabled

                widgetView.translatesAutoresizingMaskIntoConstraints = false
                widgetView.widthFactor = buttonState.widthFactor
                widgetView.heightFactor = buttonState.heightFactor
                widgetView.componentSizeFactor = buttonState.componentSizeFactor
                widgetView.borderWidth = buttonState.borderWidth
                widgetView.highlightSizeFactor = buttonState.highlightSizeFactor
                widgetView.autoTapInterval = Int(buttonState.autoTapInterval)
                widgetView.autoTapRepeats = UInt32(buttonState.autoTapRepeats)
                widgetView.setVibration(style: Int(buttonState.vibrationStyle))
                widgetView.mouseButtonAction = MouseButtonAction(rawValue: Int(buttonState.mouseButtonAction)) ?? .hovering
                widgetView.animatesTransition = buttonState.animatesTransition
                widgetView.sensitivityFactorX = buttonState.sensitivityFactorX
                widgetView.sensitivityFactorY = buttonState.sensitivityFactorY
                widgetView.slideThreshold = buttonState.slideThreshold
                widgetView.yawFactor = buttonState.yawFactor
                widgetView.pitchFactor = buttonState.pitchFactor
                widgetView.rollFactor = buttonState.rollFactor
                widgetView.decelerationRateX = buttonState.decelerationRateX
                widgetView.decelerationRateY = buttonState.decelerationRateY
                widgetView.stickIndicatorOffset = buttonState.stickIndicatorOffset
                widgetView.minStickOffset = buttonState.minStickOffset
                widgetView.dWheelWalkModeThreshold = buttonState.walkModeThreshold
                widgetView.buttonMode = ButtonMode(rawValue: Int(buttonState.buttonMode)) ?? .slideToToggle
                if widgetView.cmdString == "NOSINGLETOUCH" { widgetView.buttonMode = .movable }
                widgetView.sprintKeyActionType = OnScreenWidgetView.WalkSprintKeyActionType(rawValue: buttonState.sprintKeyActionType) ?? .hold
                widgetView.sprintKeyThreshold = buttonState.sprintKeyThreshold
                widgetView.walkKeyActionType = OnScreenWidgetView.WalkSprintKeyActionType(rawValue: buttonState.walkKeyActionType) ?? .hold
                widgetView.walkKeyThreshold = buttonState.walkKeyThreshold

                widgetView.isHidden = !OnScreenWidgetView.enableFolderAnimation && widgetView.parentSequence != -1
                // Added to the view before it is located (StreamView.m:1058).
                addSubview(widgetView)
                let position = denormalizedWidgetPosition(buttonState.position)
                widgetView.setLocation(position: position)
                widgetView.sizeReference = sizeReference.rawValue
                widgetView.resizeWidgetView()   // after relocation
                widgetView.adjustTransparency(alpha: buttonState.backgroundAlpha, tweakBorderAlpha: false)
                widgetView.adjustBorder(width: buttonState.borderWidth)
                widgetView.tweakLabelAlpha(alpha: buttonState.labelAlpha)
                widgetView.tweakBorderAlpha(alpha: buttonState.borderAlpha)
                widgetView.tweakHighlightAlpha(alpha: buttonState.highlightAlpha)
                widgetView.setupAutoTapTimer()
                widgetView.setupInertialScroller(fps: 60)   // upstream: the stream's frame rate
                ///
                widgetView.sensitivityFactorX = buttonState.sensitivityFactorX
                widgetView.componentSizeFactor = buttonState.componentSizeFactor
                widgetView.touchPointAnchored = buttonState.touchPointAnchored
                widgetView.stickIndicatorOffset = buttonState.stickIndicatorOffset

                if widgetView.isFolder && widgetView.parentSequence < 0 && widgetView.autoDockIdleDuration > 0 {
                    widgetView.setAutoDock(enabled: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        if !AlertControllerUtil.isCountingDown { widgetView.restartAutoDockCountdown() }
                    }
                }

                if sequenceGenerated {
                    buttonState.sequence = widgetView.sequence
                    if let data = try? NSKeyedArchiver.archivedData(withRootObject: buttonState, requiringSecureCoding: true) {
                        profile.buttonStatesEncoded[i] = data
                    }
                }

                widgetView.accessWidgetAttributes()
                widgetView.setupAtrributedText()   // relies on "labeledFolder" cmd
            } else if buttonState.widgetType == 0 {   // LegacyOnScreenControls
                hasLegacyWidget = true
            }
        }

        // StreamView.m:1099
        if sequenceGenerated && hasMovableWidget {
            manager.replaceSelectedProfile(with: profile, overwriteDefault: true)
        }

        // StreamView.m:1104-1119 -- touch pads and motion buttons sit below the topmost button.
        if let deepestButton = OnScreenWidgetView.deepestButton {
            var motionControlButtons = Set<OnScreenWidgetView>()
            for case let widget as OnScreenWidgetView in subviews {
                if widget.widgetType == .touchPad { insertSubview(widget, belowSubview: deepestButton) }
                if widget.isMotionControlButton { motionControlButtons.insert(widget) }
            }
            for button in motionControlButtons { insertSubview(button, belowSubview: deepestButton) }
        }

        // StreamView.m:1122-1126
        OnScreenWidgetView.unfoldedExclusiveFolderSequence = profile.unfoldedExclusiveFolderSequence
        OnScreenWidgetView.setPostExclusiveUnfoldeds(profile.postExclusiveUnfoldedSequences as NSSet)
        OnScreenWidgetView.restoreFoldedStates()

        // StreamView.m:1130-1133 -- legacy controller layers, only when the profile has some.
        if hasLegacyWidget {
            osc?.showLegacyWidgets(with: profile)
        } else {
            osc?.setLevel(.off)
        }
        OnScreenWidgetView.profileChangedDuringStreaming = false
    }

    /// StreamView.m:882 -- normalised positions are fractions of this view's bounds.
    private func denormalizedWidgetPosition(_ position: CGPoint) -> CGPoint {
        guard position.x < 2.01, position.y < 2.01 else { return position }
        return CGPoint(x: position.x * bounds.width, y: position.y * bounds.height)
    }

    // MARK: Saving (StreamView.m saveStreamingGameProfileChanges)

    /// A movable widget the player dragged, and folder states, belong to the profile.
    func persistChanges() {
        guard !suspended, !OnScreenWidgetView.editMode else { return }
        var relocated = Set<Int16>()
        var folderStateChanged = false
        for widget in OnScreenWidgetView.mapping.values {
            if widget.relocatedDuringStreaming { relocated.insert(widget.sequence) }
            if !folderStateChanged { folderStateChanged = widget.folded != widget.persistedFolded }
        }
        if relocated.isEmpty && !folderStateChanged && !OnScreenWidgetView.profileChangedDuringStreaming { return }

        // The widgets were laid out for builtSize, which differs from `bounds` right after a rotation.
        let layoutBounds = builtSize == .zero ? bounds : CGRect(origin: .zero, size: builtSize)
        let manager = OSCProfilesManager.sharedManager(layoutBounds)
        let profile = manager.getSelectedProfile()
        // The player may have switched profile since the widgets were built.
        guard profile.name == builtProfileName else { return }

        for i in 0..<profile.buttonStatesEncoded.count {
            guard let encoded = profile.buttonStatesEncoded[i] as? Data else { continue }
            let state = manager.unarchiveButtonStateEncoded(encoded)
            guard let widget = OnScreenWidgetView.mapping[state.sequence] else { continue }
            if relocated.contains(widget.sequence) || widget.isFolder {
                state.position = manager.normalizeWidgetPosition(widget.storedCenter)
                state.folded = widget.folded
                if let data = try? NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true) {
                    profile.buttonStatesEncoded[i] = data
                }
            }
        }
        profile.unfoldedExclusiveFolderSequence = OnScreenWidgetView.unfoldedExclusiveFolderSequence
        profile.postExclusiveUnfoldedSequences = Set(OnScreenWidgetView.postExclusiveUnfoldedSequences.map { NSNumber(value: $0) })
        manager.replaceSelectedProfile(with: profile, overwriteDefault: true)

        // Written: the same widgets must not write it again.
        for widget in OnScreenWidgetView.mapping.values {
            widget.relocatedDuringStreaming = false
            widget.persistedFolded = widget.folded
        }
        OnScreenWidgetView.profileChangedDuringStreaming = false
    }
}
