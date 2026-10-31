import Foundation

// Extra verification that keeps the harness honest against the app sources it mirrors.

private func read(_ repo: String, _ rel: String) throws -> String {
    try String(contentsOfFile: repo + "/" + rel, encoding: .utf8)
}

/// Class names inside `NAME ... = [ X.self, ... ]` in a Swift source.
private func classList(in text: String, after marker: String, file: String) throws -> [String] {
    guard let r = text.range(of: marker) else { throw Fail("\(file): '\(marker)' not found") }
    let rest = text[r.upperBound...]
    guard let end = rest.firstIndex(of: "]") else { throw Fail("\(file): unterminated list after '\(marker)'") }
    let body = String(rest[..<end])
    let re = try NSRegularExpression(pattern: "([A-Za-z0-9_]+)\\.self")
    let ns = body as NSString
    return re.matches(in: body, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
}

/// Raw values of an `enum NAME` block (explicit `= N` or implicit counting).
private func enumValues(_ text: String, _ name: String) throws -> [String: Int] {
    guard let r = text.range(of: "enum \(name):") else { throw Fail("enum \(name) not found") }
    let rest = text[r.upperBound...]
    guard let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") else { throw Fail("enum \(name): braces not found") }
    var out: [String: Int] = [:]
    var next = 0
    for line in rest[rest.index(after: open)..<close].components(separatedBy: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("case ") else { continue }
        let body = t.dropFirst(5).components(separatedBy: "//")[0]
        for part in body.split(separator: ",") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2 {
                next = kv[1].hasPrefix("0x") ? Int(kv[1].dropFirst(2), radix: 16)! : Int(kv[1])!
            }
            out[kv[0]] = next
            next += 1
        }
    }
    return out
}

/// The harness mirrors three things from the app; fail if the app moved on.
func checkParity(repo: String) throws {
    // 1. Secure-coding whitelists.
    let mgr = try read(repo, "app/Madeira/VLTouch/Model/OSCProfilesManager.swift")
    let f = "OSCProfilesManager.swift"
    let pc = try classList(in: mgr, after: "profileCodingClasses: [AnyClass] = [", file: f)
    let bc = try classList(in: mgr, after: "buttonStateCodingClasses: [AnyClass] = [", file: f)
    guard pc == profileCodingClasses.map({ String(describing: $0) }) else { throw Fail("profileCodingClasses drifted: app \(pc)") }
    guard bc == buttonStateCodingClasses.map({ String(describing: $0) }) else { throw Fail("buttonStateCodingClasses drifted: app \(bc)") }
    let sel = try read(repo, "app/Madeira/VLTouch/Pickers/ProfileSelectorViewController.swift")
    let oc = try classList(in: sel, after: "let classes: [AnyClass] = [", file: "ProfileSelectorViewController.swift")
    guard oc == importOuterClasses.map({ String(describing: $0) }) else { throw Fail("import outer classes drifted: app \(oc)") }
    print("parity: secure-coding class lists match OSCProfilesManager.swift:52-65 and ProfileSelectorViewController.swift:1025")

    // 2. Constants the ObjC decoders use for missing keys (shim/Madeira-Swift.h).
    let dm = try read(repo, "app/Madeira/VLTouch/Compat/VLDataManager.swift")
    let gs = try enumValues(dm, "ControllerGyroSwitchMode")
    let tm = try enumValues(dm, "TouchMode")
    let ws = try enumValues(try read(repo, "app/Madeira/VLTouch/Widgets/OnScreenWidgetView.swift"), "WalkSprintKeyActionType")
    let ce = try enumValues(try read(repo, "app/Madeira/VLTouch/Compat/VLControllerNavigator.swift"), "ControllerElement")
    let pairs: [(String, Int, Int?)] = [
        ("ControllerGyroSwitchModeDisabled", Int(ControllerGyroSwitchModeDisabled), gs["disabled"]),
        ("TouchModeNative", Int(TouchModeNative), tm["native"]),
        ("TouchModeNativeOnly", Int(TouchModeNativeOnly), tm["nativeOnly"]),
        ("WalkSprintKeyActionTypeHold", Int(WalkSprintKeyActionTypeHold), ws["hold"]),
        ("ControllerElementNull", Int(ControllerElementNull), ce["null"]),
    ]
    for (n, shim, app) in pairs where shim != app {
        throw Fail("shim constant \(n) = \(shim) but the app source says \(String(describing: app))")
    }
    print("parity: \(pairs.count) shim enum constants match the app's Swift enums")
}

/// Every cmdString token of every decoded widget must exist in CommandManager's tables.
func checkTokens(_ profiles: [DecodedProfile], tables: CommandTables) throws {
    var tokens = 0
    var widgets = 0
    for d in profiles {
        for s in d.states {
            do { tokens += try tables.validate(cmd: s.name).count } catch { throw Fail("\(d.profile.name): \(error)") }
            widgets += 1
        }
    }
    print("tokens OK: \(tokens) tokens in \(widgets) decoded widgets all exist in CommandManager's tables")
}

/// Decoder parity: the bundled templates go through the very same decode path.
func checkBundledTemplate(repo: String, tables: CommandTables) throws {
    let rel = "app/Madeira/VLTouch/Model/widgetTemplatesIPhone.bin"
    let data = try Data(contentsOf: URL(fileURLWithPath: repo + "/" + rel))
    let decoded = try decodeExport(data)
    print("template \(rel): \(decoded.count) profiles, \(decoded.reduce(0) { $0 + $1.states.count }) widgets decoded")
    var checkedPositions = 0
    for d in decoded {
        let bad = d.states.filter { (try? tables.validate(cmd: $0.name)) == nil }.count
        let sane = d.states.filter { $0.position.x > 0 && $0.position.x <= 1.0 && $0.position.y > 0 && $0.position.y <= 1.0 }.count
        checkedPositions += sane
        print("  \(d.profile.name): \(d.states.count) widgets, \(sane) with a normalized position in (0,1], \(bad) with non-table cmd strings (legacy layer names / localized aliases)")
    }
    guard let kbm = decoded.first(where: { $0.profile.name == "=kbmfps" }) else { throw Fail("template: '=kbmfps' not found") }
    for s in kbm.states.prefix(4) {
        print("  =kbmfps sample: \(s.name) alias '\(s.alias)' pos \(fmtPos(s.position)) shape \(s.widgetShape) mode \(s.buttonMode) size factor \(s.widthFactor)x\(s.heightFactor)")
    }
    // The bundled templates change between VoidLink drops, so no hard-coded counts; check structure instead.
    guard let wasd = kbm.states.first(where: { $0.name == "WASDPAD-SHIFT-CTRL" }),
          wasd.position.x > 0, wasd.position.x < 1, wasd.position.y > 0, wasd.position.y < 1, wasd.widgetShape == "largeSquare" else {
        throw Fail("template decode parity: =kbmfps has no WASDPAD-SHIFT-CTRL largeSquare widget with a normalized position")
    }
    let total = decoded.reduce(0) { $0 + $1.states.count }
    guard checkedPositions == total else {
        throw Fail("template decode parity: only \(checkedPositions) of \(total) positions decoded in (0,1] (CGPoint coding shim wrong?)")
    }
    guard decoded.count >= 7, decoded.contains(where: { $0.profile.name == "Default" }) else {
        throw Fail("template decode parity: expected the bundled profile set (Default, =vGamepad*, =kbmfps, ...)")
    }
    print("template decode OK: \(decoded.count) profiles, \(total) widgets, every position decoded to a normalized point, =kbmfps WASDPAD-SHIFT-CTRL at \(fmtPos(wasd.position))")
}
