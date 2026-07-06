import Foundation
import Observation

/// A text-first calculator (à la Numi): type an expression and see the result
/// live. Uses a small hand-written parser — never `NSExpression`, which raises
/// uncatchable ObjC exceptions on malformed input. Keeps a persistent history.
@MainActor
@Observable
final class CalcManager {
    static let shared = CalcManager()

    struct Entry: Identifiable, Codable, Equatable {
        var id = UUID()
        var expr: String
        var result: String
    }

    var input = ""
    private(set) var history: [Entry] = []
    private let key = "hubos.calc.history"
    private let maxHistory = 20

    private init() { load() }

    /// The formatted live result of `input`, or nil if it doesn't evaluate.
    var liveResult: String? {
        guard let v = Self.evaluate(input) else { return nil }
        return Self.format(v)
    }

    /// Commits the current input to history (if it evaluates) and clears it.
    func commit() {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let r = liveResult else { return }
        history.removeAll { $0.expr == trimmed }
        history.insert(Entry(expr: trimmed, result: r), at: 0)
        if history.count > maxHistory { history.removeLast(history.count - maxHistory) }
        save()
        input = ""
    }

    func reuse(_ entry: Entry) { input = entry.expr }
    func clear() { history.removeAll(); save() }

    static func format(_ v: Double) -> String {
        guard v.isFinite else { return "—" }
        if v == v.rounded() && abs(v) < 1e15 { return String(Int(v)) }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 8
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    // MARK: Evaluation

    /// Evaluates an arithmetic expression (`+ - * / ( )`, `%`, `% of`, `^`), or
    /// nil if it doesn't fully parse. Crash-free by construction.
    static func evaluate(_ raw: String) -> Double? {
        var s = raw.lowercased()
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "% of", with: "*0.01*")
        s = s.filter { !$0.isWhitespace }
        guard !s.isEmpty else { return nil }
        var p = Parser(Array(s))
        guard let v = p.parseExpression(), p.done else { return nil }
        return v
    }

    private struct Parser {
        let c: [Character]
        var i = 0
        init(_ chars: [Character]) { c = chars }
        var done: Bool { i == c.count }
        func peek() -> Character? { i < c.count ? c[i] : nil }

        mutating func parseExpression() -> Double? {
            guard var acc = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                i += 1
                guard let t = parseTerm() else { return nil }
                acc = op == "+" ? acc + t : acc - t
            }
            return acc
        }
        mutating func parseTerm() -> Double? {
            guard var acc = parsePower() else { return nil }
            while let op = peek(), op == "*" || op == "/" {
                i += 1
                guard let f = parsePower() else { return nil }
                if op == "/" { guard f != 0 else { return nil }; acc /= f } else { acc *= f }
            }
            return acc
        }
        mutating func parsePower() -> Double? {
            guard let base = parseUnary() else { return nil }
            if peek() == "^" {
                i += 1
                guard let exp = parsePower() else { return nil }   // right-associative
                return pow(base, exp)
            }
            return base
        }
        mutating func parseUnary() -> Double? {
            if peek() == "-" { i += 1; return parseUnary().map { -$0 } }
            if peek() == "+" { i += 1; return parseUnary() }
            return parsePostfix()
        }
        mutating func parsePostfix() -> Double? {
            guard var v = parsePrimary() else { return nil }
            while peek() == "%" { i += 1; v /= 100 }
            return v
        }
        mutating func parsePrimary() -> Double? {
            if peek() == "(" {
                i += 1
                guard let v = parseExpression(), peek() == ")" else { return nil }
                i += 1
                return v
            }
            var num = ""
            while let ch = peek(), ch.isNumber || ch == "." { num.append(ch); i += 1 }
            return Double(num)
        }
    }

    // MARK: Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: key) }
    }
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        history = decoded
    }

    func seedPreview() {
        input = "20% of 350"
        history = [
            Entry(expr: "(1920/1080)*27", result: "48"),
            Entry(expr: "1250*1.2", result: "1500"),
            Entry(expr: "99.99*3", result: "299.97")
        ]
    }
}
