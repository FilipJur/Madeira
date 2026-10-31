import Foundation
import CryptoKit

// vlprofiles --repo <repo root> --specs <dir> --out <file>
// Builds every spec into one VoidLink profile export (VLPR container, same bytes the app's Export
// writes), then decodes it again through the app's import path and compares every property.

func arg(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

func run() throws {
    guard let repo = arg("--repo"), let specDir = arg("--specs"), let out = arg("--out") else {
        throw Fail("usage: vlprofiles --repo <repo> --specs <dir> --out <file>")
    }
    let tables = try CommandTables.load(repo: repo)
    print("CommandManager tables: keyboard \(tables.keyboard.count), osc \(tables.osc.count), mouse \(tables.mouse.count), pads \(tables.touchPads.count), functional \(tables.functional.count), motion \(tables.motion.count)")

    let specs = try loadSpecs(dir: specDir)
    var built: [BuiltProfile] = []
    var errors: [String] = []
    var waivers: [String] = []
    for s in specs {
        let b = try buildProfile(s, tables: tables)
        let r = checkLayout(b)
        errors += r.errors
        waivers += r.waivers
        built.append(b)
    }
    let names = built.map { $0.spec.name }
    if Set(names).count != names.count { errors.append("duplicate profile names: \(names)") }
    for w in waivers { print("waiver: \(w)") }
    if !errors.isEmpty {
        for e in errors { print("ERROR: \(e)") }
        throw Fail("\(errors.count) layout error(s)")
    }

    // Expected values, taken before encoding.
    let expected = built.map { b in (snapshot(b.profile), b.states.map { snapshot($0) }) }
    let data = try encodeProfiles(built)
    let outURL = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: outURL, options: .atomic)
    let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    print("wrote \(out) (\(data.count) bytes, sha256 \(sha))")

    // Round trip through the app's import path.
    let decoded = try decodeExport(try Data(contentsOf: outURL))
    guard decoded.count == built.count else { throw Fail("round trip: \(decoded.count) profiles decoded, \(built.count) written") }
    var diffs: [String] = []
    for (i, d) in decoded.enumerated() {
        let b = built[i]
        print("profile \(i + 1): \(d.profile.name)  widgets: \(d.states.count)  gyro: mapGyroTo=\(d.profile.mapGyroTo.rawValue) yaw=\(d.profile.gyroSensitivityYaw) pitch=\(d.profile.gyroSensitivityPitch) roll=\(d.profile.gyroSensitivityRoll)")
        if d.profile.name != b.spec.name { diffs.append("profile \(i + 1) name \(d.profile.name) != \(b.spec.name)") }
        if d.states.count != b.states.count { diffs.append("\(b.spec.name): \(d.states.count) widgets decoded, \(b.states.count) written") ; continue }
        diffs += diffSnapshots(expected[i].0, snapshot(d.profile), ctx: "\(b.spec.name) profile")
        for (j, s) in d.states.enumerated() {
            print(String(format: "  %-22@ pos %@  %4.0fx%-4.0f pt  mode %d  seq %d parent %d", s.name as NSString, fmtPos(s.position) as NSString,
                         ptFromFactor(s.widthFactor), ptFromFactor(s.heightFactor), Int(s.buttonMode), Int(s.sequence), Int(s.parentSequence)))
            diffs += diffSnapshots(expected[i].1[j], snapshot(s), ctx: "\(b.spec.name) widget #\(j + 1) \(s.name)")
        }
    }
    if !diffs.isEmpty {
        for d in diffs { print("ROUND-TRIP MISMATCH: \(d)") }
        throw Fail("round trip failed (\(diffs.count) mismatches)")
    }
    print("round-trip OK: \(decoded.count) profiles, \(decoded.reduce(0) { $0 + $1.states.count }) widgets, all properties equal")
    try checkTokens(decoded, tables: tables)
    try checkParity(repo: repo)
    try checkBundledTemplate(repo: repo, tables: tables)
    print("ALL CHECKS PASSED")
}

do { try run() } catch {
    FileHandle.standardError.write(Data("vlprofiles: \(error)\n".utf8))
    exit(1)
}
