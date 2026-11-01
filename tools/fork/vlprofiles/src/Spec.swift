import Foundation
import ObjectiveC

// MARK: - Constants

/// iPhone 15 Pro: 2556x1179 px at 460 ppi, 3x scale -> 852x393 pt landscape.
let refWidth = 852.0
let refHeight = 393.0
let ptPerMM = 460.0 / 25.4 / 3.0
let minPrimaryPt = 15.0 * ptPerMM          // 90.6 pt: Xbox/TAK minimum for primary controls
let minSecondaryPt = 70.0                   // hard floor for waived (secondary) widgets
let safeLeft = 59.0, safeRight = 59.0, safeTop = 8.0, safeBottom = 21.0
let profilePrefix = "[x] "

// MARK: - Spec model

struct WidgetSpec {
    var id: String?
    var cmd: String
    var label: String
    var pos: (Double, Double)
    var sizePt: (Double, Double)?
    var shape: String
    var parent: String?
    var primary: Bool
    var waiver: String?
    var comment: String?
    var props: [String: Any]
}

struct ProfileSpec {
    var file: String
    var name: String
    var comment: String?
    var profileProps: [String: Any]
    var widgets: [WidgetSpec]
}

// MARK: - JSON helpers

private func obj(_ v: Any?, _ ctx: String) throws -> [String: Any] {
    guard let d = v as? [String: Any] else { throw Fail("\(ctx): expected an object") }
    return d
}

private func checkKeys(_ d: [String: Any], allowed: Set<String>, _ ctx: String) throws {
    for k in d.keys where !allowed.contains(k) {
        throw Fail("\(ctx): unknown key '\(k)' (allowed: \(allowed.sorted().joined(separator: ", ")))")
    }
}

private func num(_ v: Any?, _ ctx: String) throws -> Double {
    guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { throw Fail("\(ctx): expected a number") }
    return n.doubleValue
}

private func pair(_ v: Any?, _ ctx: String) throws -> (Double, Double) {
    guard let a = v as? [Any], a.count == 2 else { throw Fail("\(ctx): expected [a, b]") }
    return (try num(a[0], ctx), try num(a[1], ctx))
}

func loadSpecs(dir: String) throws -> [ProfileSpec] {
    let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".json") }.sorted()
    guard !files.isEmpty else { throw Fail("no *.json specs in \(dir)") }
    return try files.map { f in
        let data = try Data(contentsOf: URL(fileURLWithPath: dir + "/" + f))
        let root: Any
        do { root = try JSONSerialization.jsonObject(with: data) } catch { throw Fail("\(f): invalid JSON: \(error)") }
        return try parseSpec(try obj(root, f), file: f)
    }
}

func parseSpec(_ d: [String: Any], file: String) throws -> ProfileSpec {
    try checkKeys(d, allowed: ["name", "comment", "profile", "widgets"], file)
    guard let name = d["name"] as? String else { throw Fail("\(file): missing 'name'") }
    guard name.hasPrefix(profilePrefix) else { throw Fail("\(file): profile name '\(name)' must start with '\(profilePrefix)'") }
    let profileProps = d["profile"] == nil ? [:] : try obj(d["profile"], "\(file): profile")
    guard let wl = d["widgets"] as? [Any], !wl.isEmpty else { throw Fail("\(file): 'widgets' must be a non-empty list") }
    var widgets: [WidgetSpec] = []
    for (i, raw) in wl.enumerated() {
        let ctx = "\(file) widget #\(i + 1)"
        let w = try obj(raw, ctx)
        try checkKeys(w, allowed: ["id", "cmd", "label", "pos", "sizePt", "shape", "parent", "primary", "waiver", "comment", "props"], ctx)
        guard let cmd = w["cmd"] as? String else { throw Fail("\(ctx): missing 'cmd'") }
        let pos = try pair(w["pos"], "\(ctx) '\(cmd)' pos")
        var size: (Double, Double)? = nil
        if w["sizePt"] != nil { size = try pair(w["sizePt"], "\(ctx) '\(cmd)' sizePt") }
        widgets.append(WidgetSpec(
            id: w["id"] as? String, cmd: cmd, label: (w["label"] as? String) ?? "", pos: pos, sizePt: size,
            shape: (w["shape"] as? String) ?? "", parent: w["parent"] as? String,
            primary: (w["primary"] as? Bool) ?? false, waiver: w["waiver"] as? String, comment: w["comment"] as? String,
            props: w["props"] == nil ? [:] : try obj(w["props"], "\(ctx) '\(cmd)' props")))
    }
    return ProfileSpec(file: file, name: name, comment: d["comment"] as? String,
                       profileProps: profileProps, widgets: widgets)
}

// MARK: - Model property access (real names, checked against the ObjC runtime)

func propertyAttributes(_ cls: AnyClass) -> [String: String] {
    var count: UInt32 = 0
    var out: [String: String] = [:]
    guard let list = class_copyPropertyList(cls, &count) else { return out }
    for i in 0..<Int(count) {
        let p = list[i]
        out[String(cString: property_getName(p))] = String(cString: property_getAttributes(p)!)
    }
    free(list)
    return out
}

let enumNames: [String: [String: Int]] = [
    "buttonMode": ["slideToToggle": 0, "slideAndHold": 1, "regular": 2, "tapToToggle": 3, "movable": 4],
    "mouseButtonAction": ["hovering": 0, "leftButtonDown": 1, "middleButtonDown": 2, "rightButtonDown": 3, "noClick": 4],
    "revealMode": ["coexist": 0, "exclusive": 1],
    "sizeReference": ["longSide": 0, "shortSide": 1],
    "sprintKeyActionType": ["hold": 0, "toggle": 1],
    "walkKeyActionType": ["hold": 0, "toggle": 1],
    "mapGyroTo": ["mapGyroToMouse": 0, "mouse": 0, "mapGyroToControllerStick": 1, "stick": 1, "driftCorrection": 2],
]

let shapeNames: Set<String> = ["default", "round", "square", "largeSquare"]

/// Sets `props` on `target` through KVC. Unknown names, managed names and wrong value types are errors.
func applyProps(_ target: NSObject, _ props: [String: Any], managed: Set<String>, ctx: String) throws {
    let attrs = propertyAttributes(type(of: target))
    for (key, value) in props.sorted(by: { $0.key < $1.key }) {
        guard let attr = attrs[key] else {
            throw Fail("\(ctx): unknown property '\(key)' on \(type(of: target)) (valid: \(attrs.keys.filter { !managed.contains($0) }.sorted().joined(separator: ", ")))")
        }
        if managed.contains(key) { throw Fail("\(ctx): property '\(key)' is set by the generator, not via props") }
        if attr.hasPrefix("T@\"NSString\"") {
            guard let s = value as? String else { throw Fail("\(ctx): '\(key)' expects a string") }
            if key == "widgetShape", !shapeNames.contains(s) { throw Fail("\(ctx): widgetShape '\(s)' not one of \(shapeNames.sorted())") }
            target.setValue(s, forKey: key)
        } else if let t = attr.dropFirst().first, "cCsSiIlLqQfdB".contains(t) {
            if let s = value as? String {
                guard let v = enumNames[key]?[s] else { throw Fail("\(ctx): '\(key)' = '\(s)' is not a known name (\(enumNames[key]?.keys.sorted().joined(separator: ", ") ?? "numeric property"))") }
                target.setValue(NSNumber(value: v), forKey: key)
            } else if let n = value as? NSNumber {
                target.setValue(n, forKey: key)
            } else {
                throw Fail("\(ctx): '\(key)' expects a number, bool or enum name")
            }
        } else {
            throw Fail("\(ctx): property '\(key)' has an unsupported type (\(attr))")
        }
    }
}

let managedButtonProps: Set<String> = ["name", "alias", "position", "sequence", "parentSequence", "sequenceSet", "widgetType", "widgetShape", "buttonStatesEncoded"]
let managedProfileProps: Set<String> = ["name", "buttonStatesEncoded", "isSelected", "unfoldedExclusiveFolderSequence",
                                        "postExclusiveUnfoldedSequences", "pressureCurvePoints", "normalizedStreamViewOffset"]

// MARK: - Build

struct WidgetGeometry {
    var cx: Double, cy: Double, w: Double, h: Double
    var round: Bool
    var isPad: Bool
    var backdrop: Bool
    var parentIndex: Int?
    var index: Int
    var cmd: String
    var primary: Bool
    var waiver: String?
}

struct BuiltProfile {
    var spec: ProfileSpec
    var profile: OSCProfile
    var states: [OnScreenButtonState]
    var geometry: [WidgetGeometry]
    var notes: [String]
}

func buildProfile(_ spec: ProfileSpec, tables: CommandTables) throws -> BuiltProfile {
    let ctxP = spec.file
    let profile = VLNewDefaultProfile() as! OSCProfile
    profile.name = spec.name
    profile.isSelected = false
    try applyProps(profile, spec.profileProps, managed: managedProfileProps, ctx: "\(ctxP) profile")

    // Folder tree: spec ids -> 1-based sequences.
    var seqById: [String: Int] = [:]
    for (i, w) in spec.widgets.enumerated() {
        if let id = w.id {
            if seqById[id] != nil { throw Fail("\(ctxP): duplicate widget id '\(id)'") }
            seqById[id] = i + 1
        }
    }

    var states: [OnScreenButtonState] = []
    var geo: [WidgetGeometry] = []
    var notes: [String] = []
    var childrenOf: [Int: Set<Int>] = [:]

    for (i, w) in spec.widgets.enumerated() {
        let ctx = "\(ctxP) widget #\(i + 1) '\(w.cmd)'"
        let tokens = try tables.validate(cmd: w.cmd)
        let isPad = tables.touchPads.contains(tokens[0])
        let isFolder = tokens[0] == "FOLDER" || tokens[0] == "LABELEDFOLDER"
        let isMotion = tokens.contains { tables.motion.contains($0) }

        var shape = w.shape
        if shape.isEmpty { shape = isPad ? "largeSquare" : "round" }
        guard shapeNames.contains(shape) else { throw Fail("\(ctx): shape '\(shape)' invalid") }
        if isPad && shape != "largeSquare" { throw Fail("\(ctx): touchpads are always largeSquare in the app; set shape 'largeSquare' or omit") }
        if !isPad && shape == "largeSquare" { throw Fail("\(ctx): only touchpads use largeSquare") }

        let s = VLNewDefaultButtonState() as! OnScreenButtonState
        s.name = w.cmd
        s.alias = w.label
        s.widgetType = 1                                    // CustomOnScreenWidget
        s.widgetShape = shape
        s.sequence = Int16(i + 1)
        s.parentSequence = -1
        guard w.pos.0 > 0, w.pos.0 < 1, w.pos.1 > 0, w.pos.1 < 1 else { throw Fail("\(ctx): pos must be fractions in (0,1), got \(w.pos)") }
        s.position = CGPoint(x: w.pos.0, y: w.pos.1)

        // Size: sizePt -> normalized per-10000 of the long side, exactly what the editor saves (>10 = normalized).
        var size = w.sizePt
        if size == nil {
            guard w.props["widthFactor"] != nil else { throw Fail("\(ctx): give sizePt (or widthFactor/heightFactor in props)") }
        } else {
            if w.props["widthFactor"] != nil || w.props["heightFactor"] != nil { throw Fail("\(ctx): sizePt and width/heightFactor are mutually exclusive") }
            if shape == "round" {
                guard size!.0 == size!.1 else { throw Fail("\(ctx): round widgets need a square sizePt") }
            }
            s.widthFactor = CGFloat(size!.0 / refWidth * 10000)
            s.heightFactor = CGFloat(size!.1 / refWidth * 10000)
            s.sizeReference = 0
        }
        if isFolder { s.folded = true }

        if let p = w.parent {
            guard let ps = seqById[p] else { throw Fail("\(ctx): parent '\(p)' not found") }
            let pw = spec.widgets[ps - 1]
            let pt = pw.cmd.split(separator: "-").first.map(String.init) ?? ""
            guard pt == "FOLDER" || pt == "LABELEDFOLDER" else { throw Fail("\(ctx): parent '\(p)' is not a folder") }
            s.parentSequence = Int16(ps)
            childrenOf[ps, default: []].insert(i + 1)
        }
        try applyProps(s, w.props, managed: managedButtonProps, ctx: ctx)
        if size == nil { size = (Double(s.widthFactor), Double(s.heightFactor)) }   // spec-supplied factors: no pt check

        let (gw, gh) = (size!.0, size!.1)
        states.append(s)
        let backdrop = isPad && gw >= 0.9 * refWidth && gh >= 0.9 * refHeight
        geo.append(WidgetGeometry(cx: w.pos.0 * refWidth, cy: w.pos.1 * refHeight, w: gw, h: gh, round: shape == "round",
                                  isPad: isPad, backdrop: backdrop,
                                  parentIndex: w.parent.map { seqById[$0]! - 1 }, index: i, cmd: w.cmd,
                                  primary: w.primary, waiver: w.waiver))
    }
    for (seq, kids) in childrenOf {
        states[seq - 1].sequenceSet = Set(kids.map { NSNumber(value: $0) })
    }
    return BuiltProfile(spec: spec, profile: profile, states: states, geometry: geo, notes: notes)
}

// MARK: - Layout checks (sizes, safe area, overlaps)

struct CheckReport {
    var errors: [String] = []
    var waivers: [String] = []
}

func checkLayout(_ b: BuiltProfile) -> CheckReport {
    var r = CheckReport()
    let name = b.spec.name
    func desc(_ g: WidgetGeometry) -> String { "\(name): #\(g.index + 1) \(g.cmd)" }
    for g in b.geometry {
        if g.backdrop { continue }
        let minSide = min(g.w, g.h)
        let mm = minSide / ptPerMM
        if minSide + 0.01 < minPrimaryPt {
            if g.primary {
                r.errors.append("\(desc(g)): primary widget \(Int(g.w))x\(Int(g.h)) pt (\(String(format: "%.1f", mm)) mm) is below the 15 mm floor (\(String(format: "%.1f", minPrimaryPt)) pt)")
            } else if minSide + 0.01 < minSecondaryPt {
                r.errors.append("\(desc(g)): \(Int(g.w))x\(Int(g.h)) pt is below the \(Int(minSecondaryPt)) pt hard floor")
            } else if let w = g.waiver, !w.isEmpty {
                r.waivers.append("\(desc(g)) \(Int(g.w))x\(Int(g.h)) pt (\(String(format: "%.1f", mm)) mm): \(w)")
            } else {
                r.errors.append("\(desc(g)): \(Int(g.w))x\(Int(g.h)) pt (\(String(format: "%.1f", mm)) mm) is below 15 mm and has no 'waiver' string")
            }
        }
        let l = g.cx - g.w / 2, rr = g.cx + g.w / 2, t = g.cy - g.h / 2, bt = g.cy + g.h / 2
        if l < safeLeft - 0.5 || rr > refWidth - safeRight + 0.5 || t < safeTop - 0.5 || bt > refHeight - safeBottom + 0.5 {
            r.errors.append("\(desc(g)): rect x \(Int(l))..\(Int(rr)) y \(Int(t))..\(Int(bt)) leaves the safe area x \(Int(safeLeft))..\(Int(refWidth - safeRight)) y \(Int(safeTop))..\(Int(refHeight - safeBottom))")
        }
    }

    func overlaps(_ a: WidgetGeometry, _ c: WidgetGeometry) -> Bool {
        if a.round && c.round { return hypot(a.cx - c.cx, a.cy - c.cy) < (a.w + c.w) / 2 - 0.01 }
        let ax = abs(a.cx - c.cx) < (a.w + c.w) / 2 - 0.01
        let ay = abs(a.cy - c.cy) < (a.h + c.h) / 2 - 0.01
        guard ax && ay else { return false }
        if a.round != c.round {
            // circle vs rect: nearest rect point to the circle centre
            let (circ, rect) = a.round ? (a, c) : (c, a)
            let nx = min(max(circ.cx, rect.cx - rect.w / 2), rect.cx + rect.w / 2)
            let ny = min(max(circ.cy, rect.cy - rect.h / 2), rect.cy + rect.h / 2)
            return hypot(circ.cx - nx, circ.cy - ny) < circ.w / 2 - 0.01
        }
        return true
    }
    // Widgets that can be visible at the same time: all top-level ones plus one folder's children.
    let folderIdx = Set(b.geometry.compactMap { $0.parentIndex })
    let top = b.geometry.filter { $0.parentIndex == nil }
    var groups: [[WidgetGeometry]] = [top]
    for f in folderIdx.sorted() { groups.append(top + b.geometry.filter { $0.parentIndex == f }) }
    var seen = Set<String>()
    for grp in groups {
        for i in 0..<grp.count {
            for j in (i + 1)..<max(grp.count, i + 1) {
                let a = grp[i], c = grp[j]
                if a.isPad != c.isPad { continue }                 // pads render below buttons on purpose
                if a.isPad && (a.backdrop || c.backdrop) { continue }
                let key = "\(min(a.index, c.index))-\(max(a.index, c.index))"
                if seen.contains(key) { continue }
                if overlaps(a, c) {
                    seen.insert(key)
                    r.errors.append("\(name): #\(a.index + 1) \(a.cmd) overlaps #\(c.index + 1) \(c.cmd)")
                }
            }
        }
    }
    return r
}

// MARK: - Encoding (same calls as the app's export path)

func encodeProfiles(_ built: [BuiltProfile]) throws -> Data {
    let encodedProfiles = NSMutableArray()
    for b in built {
        let states = NSMutableArray()
        for s in b.states {
            states.add(try NSKeyedArchiver.archivedData(withRootObject: s, requiringSecureCoding: true))
        }
        b.profile.setValue(states, forKey: "buttonStatesEncoded")
        encodedProfiles.add(try NSKeyedArchiver.archivedData(withRootObject: b.profile, requiringSecureCoding: true))
    }
    let payload = try NSKeyedArchiver.archivedData(withRootObject: encodedProfiles, requiringSecureCoding: true)
    return ProfileFileContainer.packedData(from: payload)
}
