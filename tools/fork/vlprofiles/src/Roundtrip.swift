import Foundation
import ObjectiveC

// Secure-coding whitelists, same lists as the app:
//   fileToProfiles            ProfileSelectorViewController.swift:1025  [NSMutableData, NSMutableArray]
//   OSCProfilesManager        profileCodingClasses / buttonStateCodingClasses (OSCProfilesManager.swift:52-65)
let importOuterClasses: [AnyClass] = [NSMutableData.self, NSMutableArray.self]
let profileCodingClasses: [AnyClass] = [NSString.self, NSMutableData.self, NSMutableArray.self, OSCProfile.self, OnScreenButtonState.self]
let buttonStateCodingClasses: [AnyClass] = [NSString.self, OnScreenButtonState.self, NSSet.self, NSNumber.self]

struct DecodedProfile {
    var profile: OSCProfile
    var states: [OnScreenButtonState]
}

/// The app's import path: ProfileFileContainer.unpackedData -> unarchive outer array ->
/// OSCProfilesManager.decodeProfiles -> unarchiveButtonStateEncoded per widget.
func decodeExport(_ file: Data) throws -> [DecodedProfile] {
    let payload = try ProfileFileContainer.unpackedData(from: file)
    guard let outer = try NSKeyedUnarchiver.unarchivedObject(ofClasses: importOuterClasses, from: payload) as? NSMutableArray,
          outer.count > 0 else { throw Fail("outer archive is not a non-empty NSMutableArray") }
    var result: [DecodedProfile] = []
    for case let enc as Data in outer {
        guard let p = try NSKeyedUnarchiver.unarchivedObject(ofClasses: profileCodingClasses, from: enc) as? OSCProfile else {
            throw Fail("profile blob did not decode as OSCProfile")
        }
        var states: [OnScreenButtonState] = []
        let list = p.buttonStatesEncoded as NSArray? ?? []
        for case let sd as Data in list {
            guard let s = try NSKeyedUnarchiver.unarchivedObject(ofClasses: buttonStateCodingClasses, from: sd) as? OnScreenButtonState else {
                throw Fail("widget blob in '\(p.name)' did not decode as OnScreenButtonState")
            }
            states.append(s)
        }
        result.append(DecodedProfile(profile: p, states: states))
    }
    return result
}

// MARK: - Snapshot compare (every real property)

func snapshot(_ o: NSObject) -> [String: Any] {
    var out: [String: Any] = [:]
    for (k, attr) in propertyAttributes(type(of: o)) {
        if k == "buttonStatesEncoded" { continue }
        if attr.hasPrefix("T{CGPoint") {
            if let v = o.value(forKey: k) as? NSValue {
                out[k] = [Double(Float(v.pointValue.x)), Double(Float(v.pointValue.y))]
            }
        } else if let v = o.value(forKey: k) {
            out[k] = v
        }
    }
    return out
}

func sameValue(_ a: Any, _ b: Any) -> Bool {
    if let x = a as? NSNumber, let y = b as? NSNumber {
        let (p, q) = (x.doubleValue, y.doubleValue)
        return abs(p - q) <= 1e-4 * max(1, abs(p), abs(q))
    }
    if let x = a as? [Double], let y = b as? [Double] { return x.count == y.count && zip(x, y).allSatisfy { abs($0 - $1) < 1e-5 } }
    if let x = a as? NSSet, let y = b as? NSSet { return x == y }
    if let x = a as? NSString, let y = b as? NSString { return x == y }
    if let x = a as? NSArray, let y = b as? NSArray { return x == y }
    return false
}

func diffSnapshots(_ expected: [String: Any], _ actual: [String: Any], ctx: String) -> [String] {
    var out: [String] = []
    for (k, e) in expected.sorted(by: { $0.key < $1.key }) {
        guard let a = actual[k] else { out.append("\(ctx): '\(k)' missing after decode"); continue }
        if !sameValue(e, a) { out.append("\(ctx): '\(k)' encoded \(e) but decoded \(a)") }
    }
    return out
}

func ptFromFactor(_ f: CGFloat) -> Double { Double(f) > 10 ? Double(f) / 10000 * refWidth : Double(f) }

func fmtPos(_ p: CGPoint) -> String { String(format: "(%.3f, %.3f)", p.x, p.y) }
