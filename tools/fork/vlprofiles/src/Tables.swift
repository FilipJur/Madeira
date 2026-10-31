import Foundation

struct Fail: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

/// Token tables read straight from app/Madeira/VLTouch/Commands/CommandManager.swift, so the
/// generator validates against the very lists the app uses (no second copy to drift).
struct CommandTables {
    let keyboard: Set<String>
    let osc: Set<String>
    let mouse: Set<String>
    let touchPads: Set<String>
    let functional: Set<String>
    let motion: Set<String>

    var all: Set<String> { keyboard.union(osc).union(mouse).union(touchPads).union(functional).union(motion) }

    static func load(repo: String) throws -> CommandTables {
        let path = repo + "/app/Madeira/VLTouch/Commands/CommandManager.swift"
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let lines = text.components(separatedBy: "\n")

        func table(_ name: String, dictionary: Bool) throws -> Set<String> {
            guard let start = lines.firstIndex(where: { $0.contains("static let \(name):") }) else {
                throw Fail("CommandManager.swift: table \(name) not found")
            }
            let keyRe = try NSRegularExpression(pattern: dictionary ? "\"([^\"]+)\"\\s*:" : "\"([^\"]+)\"")
            var depth = 0
            var out = Set<String>()
            var i = start
            var first = true
            while i < lines.count {
                var line = lines[i]
                if first {
                    guard let eq = line.range(of: "= ") else { throw Fail("table \(name): no '=' on declaration line") }
                    line = String(line[eq.upperBound...])
                    first = false
                }
                if let c = line.range(of: "//") { line = String(line[..<c.lowerBound]) }
                let ns = line as NSString
                for m in keyRe.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    out.insert(ns.substring(with: m.range(at: 1)))
                }
                for ch in line {
                    if ch == "[" { depth += 1 } else if ch == "]" { depth -= 1 }
                }
                if depth <= 0 { break }
                i += 1
            }
            if out.isEmpty { throw Fail("table \(name): parsed no entries") }
            return out
        }

        return CommandTables(
            keyboard: try table("keyboardButtonMappings", dictionary: true),
            osc: try table("oscButtonMappings", dictionary: true),
            mouse: try table("mouseButtonMappings", dictionary: true),
            touchPads: try table("touchPadCmds", dictionary: false),
            functional: try table("functionalButtonCmds", dictionary: false),
            motion: try table("motionControlButtonCmds", dictionary: false))
    }

    /// Grammar of CommandManager.extractCmdStrings (non-GUI branch): TOKEN(-TOKEN)*(-<n>MS)?.
    func validate(cmd: String) throws -> [String] {
        let parts = cmd.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, !parts.contains("") else { throw Fail("cmdString '\(cmd)': empty token") }
        let all = self.all
        for (i, p) in parts.enumerated() {
            if all.contains(p) { continue }
            if i == parts.count - 1, i > 0, p.range(of: "^[0-9]+MS$", options: .regularExpression) != nil { continue }
            throw Fail("cmdString '\(cmd)': token '\(p)' is not in CommandManager's tables")
        }
        return parts
    }
}
