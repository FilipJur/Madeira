import Foundation

// Derived profiles: a bundled VoidLink template (app/Madeira/VLTouch/Model/widgetTemplatesIPhone.bin)
// copied whole, then edited. Every property the edits do not name keeps the template's value,
// so the result keeps VoidLink's own tuning (alphas, highlight, thresholds, folders).
//
// specs/derived/*.json:
//   { "name": "[x] ...", "base": "=vGamepad1", "comment": "...",
//     "profile": { <OSCProfile props> },
//     "remove": ["PUSHTOTALK"],
//     "edits": [ { "match": "OSCA", "cmd": "GYRO-OSCA", "label": "A", "pos": [x, y], "sizePt": [w, h],
//                  "props": { <OnScreenButtonState props> } } ],
//     "add":   [ { "like": "OSCY", "cmd": "OSCY-OSCB", "label": "Y+B", "pos": [x, y], "sizePt": [w, h] } ] }
// "match" names exactly one widget of the base by its command string. An "add" copies the widget
// named by "like" (its look and tuning) under a new sequence number, then applies the same fields.

struct DerivedEdit {
    var match: String
    var cmd: String?
    var label: String?
    var pos: (Double, Double)?
    var sizePt: (Double, Double)?
    var props: [String: Any]
}

struct DerivedSpec {
    var file: String
    var name: String
    var comment: String?
    var base: String
    var profileProps: [String: Any]
    var remove: [String]
    var edits: [DerivedEdit]
    var adds: [DerivedEdit]
}

private func pairOf(_ v: Any?, _ ctx: String) throws -> (Double, Double) {
    guard let a = v as? [NSNumber], a.count == 2 else { throw Fail("\(ctx): expected [a, b]") }
    return (a[0].doubleValue, a[1].doubleValue)
}

func loadDerived(dir: String) throws -> [DerivedSpec] {
    let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".json") }.sorted()
    return try files.map { f in
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: dir + "/" + f)))
        guard let d = root as? [String: Any] else { throw Fail("\(f): expected an object") }
        for k in d.keys where !["name", "comment", "base", "profile", "remove", "edits", "add"].contains(k) {
            throw Fail("\(f): unknown key '\(k)'")
        }
        guard let name = d["name"] as? String, name.hasPrefix(profilePrefix) else { throw Fail("\(f): 'name' must start with '\(profilePrefix)'") }
        guard let base = d["base"] as? String else { throw Fail("\(f): missing 'base'") }
        func parseEdits(_ key: String, matchKey: String) throws -> [DerivedEdit] {
            try ((d[key] as? [Any]) ?? []).enumerated().map { i, raw in
                let ctx = "\(f) \(key) #\(i + 1)"
                guard let e = raw as? [String: Any], let match = e[matchKey] as? String else { throw Fail("\(ctx): needs '\(matchKey)'") }
                for k in e.keys where ![matchKey, "cmd", "label", "pos", "sizePt", "props", "comment"].contains(k) {
                    throw Fail("\(ctx): unknown key '\(k)'")
                }
                return DerivedEdit(match: match, cmd: e["cmd"] as? String, label: e["label"] as? String,
                                   pos: e["pos"] == nil ? nil : try pairOf(e["pos"], "\(ctx) pos"),
                                   sizePt: e["sizePt"] == nil ? nil : try pairOf(e["sizePt"], "\(ctx) sizePt"),
                                   props: (e["props"] as? [String: Any]) ?? [:])
            }
        }
        return DerivedSpec(file: f, name: name, comment: d["comment"] as? String, base: base,
                           profileProps: (d["profile"] as? [String: Any]) ?? [:],
                           remove: (d["remove"] as? [String]) ?? [],
                           edits: try parseEdits("edits", matchKey: "match"), adds: try parseEdits("add", matchKey: "like"))
    }
}

/// Independent copy of a decoded object through the same secure coding the app uses.
private func copyObject<T: NSObject>(_ o: T, classes: [AnyClass]) throws -> T {
    let data = try NSKeyedArchiver.archivedData(withRootObject: o, requiringSecureCoding: true)
    guard let c = try NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data) as? T else { throw Fail("copy of \(type(of: o)) failed") }
    return c
}

func buildDerived(_ d: DerivedSpec, templates: [DecodedProfile], tables: CommandTables) throws -> BuiltProfile {
    let ctxP = d.file
    guard let base = templates.first(where: { $0.profile.name == d.base }) else { throw Fail("\(ctxP): base '\(d.base)' not in the bundled template") }
    let profile = try copyObject(base.profile, classes: profileCodingClasses)
    profile.name = d.name
    profile.isSelected = false
    try applyProps(profile, d.profileProps, managed: managedProfileProps, ctx: "\(ctxP) profile")

    var states = try base.states.map { try copyObject($0, classes: buttonStateCodingClasses) }
    func index(of name: String, _ ctx: String) throws -> Int {
        let hits = states.indices.filter { states[$0].name == name }
        guard hits.count == 1 else { throw Fail("\(ctx): '\(name)' matches \(hits.count) widgets of \(d.base), need exactly 1") }
        return hits[0]
    }
    for r in d.remove {
        let i = try index(of: r, "\(ctxP) remove")
        let seq = states[i].sequence
        guard !states.contains(where: { $0.parentSequence == seq }) else { throw Fail("\(ctxP): '\(r)' is a folder with children") }
        states.remove(at: i)
    }
    var edited = Set<Int16>()
    func apply(_ e: DerivedEdit, to s: OnScreenButtonState, _ ctx: String) throws {
        if let cmd = e.cmd { _ = try tables.validate(cmd: cmd); s.name = cmd }
        if let l = e.label { s.alias = l }
        if let p = e.pos {
            guard p.0 > 0, p.0 < 1, p.1 > 0, p.1 < 1 else { throw Fail("\(ctx): pos must be fractions in (0,1)") }
            s.position = CGPoint(x: p.0, y: p.1)
        }
        if let z = e.sizePt {
            if s.widgetShape == "round", z.0 != z.1 { throw Fail("\(ctx): round widgets need a square sizePt") }
            s.widthFactor = CGFloat(z.0 / refWidth * 10000)
            s.heightFactor = CGFloat(z.1 / refWidth * 10000)
        }
        try applyProps(s, e.props, managed: managedButtonProps, ctx: ctx)
        edited.insert(s.sequence)
    }
    for (n, e) in d.edits.enumerated() {
        let ctx = "\(ctxP) edit #\(n + 1) '\(e.match)'"
        try apply(e, to: states[try index(of: e.match, ctx)], ctx)
    }
    for (n, e) in d.adds.enumerated() {
        let ctx = "\(ctxP) add #\(n + 1) like '\(e.match)'"
        guard e.cmd != nil, e.pos != nil else { throw Fail("\(ctx): an added widget needs 'cmd' and 'pos'") }
        let s = try copyObject(states[try index(of: e.match, ctx)], classes: buttonStateCodingClasses)
        s.sequence = (states.map { $0.sequence }.max() ?? 0) + 1
        s.parentSequence = -1
        s.sequenceSet = []
        states.append(s)
        try apply(e, to: s, ctx)
    }

    // Visibility groups: a widget listed in a folder's sequenceSet (or whose parentSequence names a
    // present folder) only shows while that folder is unfolded.
    var folderOf: [Int16: Int16] = [:]
    for f in states where f.name.hasPrefix("FOLDER") || f.name.hasPrefix("LABELEDFOLDER") {
        for case let n as NSNumber in (f.sequenceSet as NSSet? ?? []) { folderOf[n.int16Value] = f.sequence }
    }
    let present = Set(states.map { $0.sequence })
    for s in states where s.parentSequence >= 0 && present.contains(s.parentSequence) { folderOf[s.sequence] = s.parentSequence }
    let seqIndex = Dictionary(uniqueKeysWithValues: states.enumerated().map { ($1.sequence, $0) })
    var geo: [WidgetGeometry] = []
    for (i, s) in states.enumerated() {
        let tok = s.name.split(separator: "-").first.map(String.init) ?? s.name
        geo.append(WidgetGeometry(cx: Double(s.position.x) * refWidth, cy: Double(s.position.y) * refHeight,
                                  w: ptFromFactor(s.widthFactor), h: ptFromFactor(s.heightFactor),
                                  round: s.widgetShape == "round", isPad: tables.touchPads.contains(tok), backdrop: false,
                                  parentIndex: folderOf[s.sequence].flatMap { seqIndex[$0] }, index: i, cmd: s.name,
                                  primary: edited.contains(s.sequence), waiver: nil))
    }
    let spec = ProfileSpec(file: d.file, name: d.name, comment: d.comment, profileProps: d.profileProps, widgets: [])
    return BuiltProfile(spec: spec, profile: profile, states: states, geometry: geo)
}

/// The template's own layout ignores the generator's safe-area and size rules, and its touchpads overlap
/// each other on purpose (the top one takes the touch). A derived profile is held to one rule: no edited
/// button may overlap another button that can be on screen with it.
func checkDerived(_ b: BuiltProfile) -> [String] {
    let re = try! NSRegularExpression(pattern: "#(\\d+) ")
    return checkLayout(b).errors.filter { e in
        guard e.contains(" overlaps ") else { return false }
        let s = e as NSString
        let pair = re.matches(in: e, range: NSRange(location: 0, length: s.length)).compactMap { m in
            Int(s.substring(with: m.range(at: 1))).map { b.geometry[$0 - 1] }
        }
        return pair.count == 2 && !(pair[0].isPad && pair[1].isPad) && (pair[0].primary || pair[1].primary)
    }
}
