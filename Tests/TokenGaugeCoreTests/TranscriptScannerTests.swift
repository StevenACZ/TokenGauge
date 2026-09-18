import CryptoKit
import Foundation
import XCTest

@testable import TokenGaugeCore

final class TranscriptScannerTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-12T18:00:00Z")!

    func testIncrementalRescanReadsOnlyAppendedBytes() throws {
        try withHome { home in
            let state = home.appending(path: "support/scan-state.json")
            let claudeFile = home.appending(path: ".claude/projects/project/a.jsonl")
            let codexFile = home.appending(path: ".codex/sessions/2026/09/12/a.jsonl")
            try write(
                claudeFile,
                [
                    claude("m1", time: "12:00:00", output: 3), claude("m1", time: "12:00:01", output: 3),
                    claude("m2", time: "12:05:00", output: 5),
                ])
            try write(
                codexFile,
                [turnContext("turn-a", effort: "xhigh"), codex("r1", turn: "turn-a", time: "12:30:00", tokens: 40)])

            let cold = try scan(home, state: state)
            XCTAssertEqual(cold.bytesRead, try size(claudeFile) + size(codexFile))
            XCTAssertEqual(cold.buckets.map(\.tokens), [128])
            XCTAssertEqual(cold.effortRecords.map(\.tokens), [63, 65, 40])

            let warm = try scan(home, state: state)
            XCTAssertEqual(warm.bytesRead, 0)
            XCTAssertEqual(warm.buckets, cold.buckets)
            XCTAssertEqual(warm.effortRecords, cold.effortRecords)

            let appended = try append(
                claudeFile,
                [
                    claude("m2", time: "12:05:01", output: 9), claude("m3", time: "13:00:00", output: 7),
                    claude("m4", time: "13:10:00", output: 1),
                ])
            let incremental = try scan(home, state: state)
            XCTAssertEqual(incremental.bytesRead, appended)
            XCTAssertEqual(incremental.buckets.map(\.tokens), [132, 128])
            XCTAssertEqual(incremental.buckets, try fullBuckets(home))
            XCTAssertEqual(incremental.effortRecords, try fullRecords(home))

            let grownSize = try size(claudeFile)
            try truncate(claudeFile, to: grownSize - 10)
            try append(claudeFile, [claude("m5", time: "14:00:00", output: 2)])
            XCTAssertGreaterThan(try size(claudeFile), grownSize)
            let rewritten = try scan(home, state: state)
            XCTAssertEqual(rewritten.bytesRead, try size(claudeFile))
            XCTAssertEqual(rewritten.buckets, try fullBuckets(home))
            XCTAssertEqual(rewritten.effortRecords, try fullRecords(home))

            try truncate(claudeFile, to: Data((claude("m1", time: "12:00:00", output: 3) + "\n").utf8).count)
            let truncated = try scan(home, state: state)
            XCTAssertEqual(truncated.bytesRead, try size(claudeFile))
            XCTAssertEqual(truncated.buckets.map(\.tokens), [63])
            XCTAssertEqual(truncated.effortRecords.map(\.tokens), [63, 40])

            try FileManager.default.removeItem(at: codexFile)
            let removed = try scan(home, state: state)
            XCTAssertEqual(removed.bytesRead, 0)
            XCTAssertEqual(removed.effortRecords.map(\.provider), [.claude])

            let permissions = try FileManager.default.attributesOfItem(atPath: state.path)[.posixPermissions] as? Int
            XCTAssertEqual(permissions, 0o600)
        }
    }

    func testSinglePassMatchesTwoPassOutputs() throws {
        try withHome { home in
            let projects = home.appending(path: ".claude/projects")
            try write(
                projects.appending(path: "p1/a.jsonl"),
                [
                    claude("m1", time: "12:00:00", output: 3), claude("m1", time: "12:00:01", output: 3),
                    claude("m2", time: "12:20:00", output: 4)
                        .replacingOccurrences(of: "claude-fable-5-1", with: "<synthetic>"),
                    claude("m3", time: "12:59:58", output: 1), claude("m3", time: "13:00:02", output: 30),
                    """
                    {"type":"assistant","timestamp":"2026-09-12T14:00:00.000Z","uuid":"uuid-only","message":{"model":"claude-opus-5","usage":{"input_tokens":5,"output_tokens":5}}}
                    """,
                    """
                    {"type":"user","timestamp":"2026-09-12T14:01:00.000Z","uuid":"u1","message":{"role":"user"}}
                    """,
                    "not json",
                    claude("old", time: "12:00:00", output: 2).replacingOccurrences(
                        of: "2026-09-12", with: "2026-08-20"),
                ])
            try write(
                projects.appending(path: "p2/b.jsonl"),
                [
                    claude("m3", time: "13:00:03", output: 30),
                    claude("m5", time: "15:00:00", output: 8).replacingOccurrences(
                        of: "\"perTurnEffort\":\"medium\",", with: ""),
                ])
            let stale = projects.appending(path: "p3/stale.jsonl")
            try write(stale, [claude("stale", time: "12:00:00", output: 3)])
            try setModified(stale, Date(timeIntervalSince1970: 0))
            let aged = projects.appending(path: "p4/aged.jsonl")
            try write(
                aged,
                [claude("aged", time: "12:00:00", output: 6).replacingOccurrences(of: "2026-09-12", with: "2026-09-05")]
            )
            try setModified(aged, ISO8601DateFormatter().date(from: "2026-09-05T12:00:00Z")!)

            let sessions = home.appending(path: ".codex/sessions")
            try write(
                sessions.appending(path: "2026/09/12/a.jsonl"),
                [
                    turnContext("turn-a", effort: "xhigh"),
                    codex("r1", turn: "turn-a", time: "12:30:00", tokens: 40),
                    codex("r1", turn: "turn-a", time: "12:30:01", tokens: 40),
                    """
                    {"type":"event_msg","timestamp":"2026-09-12T12:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":9999}}}}
                    """,
                    codex("r2", turn: "absent", time: "12:31:00", tokens: 20),
                    turnContext("turn-b", effort: "high"),
                    codex("r3", turn: "turn-b", time: "12:32:00", tokens: 7),
                ])
            let resumed = sessions.appending(path: "2026/01/01/resumed.jsonl")
            try write(
                resumed,
                [
                    turnContext("turn-r", effort: "low"),
                    codex("r-old", turn: "turn-r", time: "12:00:00", tokens: 90)
                        .replacingOccurrences(of: "2026-09-12", with: "2026-01-01"),
                    codex("r-new", turn: "turn-r", time: "12:40:00", tokens: 40),
                ])
            try setModified(resumed, now)
            let recentDirectory = sessions.appending(path: "2026/09/11/b.jsonl")
            try write(
                recentDirectory,
                [
                    codex("r-yesterday", time: "12:00:00", tokens: 5).replacingOccurrences(
                        of: "2026-09-12", with: "2026-09-11")
                ])
            try setModified(recentDirectory, Date(timeIntervalSince1970: 0))

            let expectedBuckets = try ReferenceScanners.history(projectsRoot: projects, days: 8, now: now)
            let expectedRecords = try ReferenceScanners.effort(home: home, lookbackDays: 7, now: now)
            XCTAssertEqual(expectedBuckets.map(\.tokens), [66, 63, 64, 90, 10, 68])
            XCTAssertEqual(expectedRecords.map(\.tokens), [5, 63, 64, 40, 20, 7, 40, 90, 68])

            let state = home.appending(path: "support/scan-state.json")
            let single = try TranscriptScanner.scan(homeDirectory: home, stateURL: state, now: now)
            XCTAssertEqual(single.buckets, expectedBuckets)
            XCTAssertEqual(single.effortRecords, expectedRecords)
            XCTAssertEqual(try fullBuckets(home), expectedBuckets)
            XCTAssertEqual(try fullRecords(home), expectedRecords)

            let warm = try TranscriptScanner.scan(homeDirectory: home, stateURL: state, now: now)
            XCTAssertEqual(warm.bytesRead, 0)
            XCTAssertEqual(warm.buckets, expectedBuckets)
            XCTAssertEqual(warm.effortRecords, expectedRecords)
        }
    }

    func testCorruptOrRegressedStateFallsBackToFullScan() throws {
        try withHome { home in
            let state = home.appending(path: "support/scan-state.json")
            let file = home.appending(path: ".claude/projects/project/a.jsonl")
            try write(file, [claude("m1", time: "12:00:00", output: 3), claude("m2", time: "12:05:00", output: 5)])
            let total = try size(file)
            XCTAssertEqual(try scan(home, state: state).bytesRead, total)
            XCTAssertEqual(try scan(home, state: state).bytesRead, 0)

            try Data("{not json".utf8).write(to: state)
            let recovered = try scan(home, state: state)
            XCTAssertEqual(recovered.bytesRead, total)
            XCTAssertEqual(recovered.buckets.map(\.tokens), [128])

            XCTAssertEqual(try scan(home, state: state, now: now.addingTimeInterval(-86_400)).bytesRead, total)
            XCTAssertEqual(try scan(home, state: state).bytesRead, 0)
        }
    }

    private func scan(_ home: URL, state: URL, now: Date? = nil) throws -> TranscriptScanner.Result {
        try TranscriptScanner.scan(homeDirectory: home, stateURL: state, now: now ?? self.now)
    }

    private func fullBuckets(_ home: URL) throws -> [ModelTokenBucket] {
        try ClaudeHistoryScanner.scan(projectsRoot: home.appending(path: ".claude/projects"), now: now)
    }

    private func fullRecords(_ home: URL) throws -> [EffortUsageRecord] {
        try EffortUsageScanner.scan(homeDirectory: home, now: now)
    }

    private func withHome(_ body: (URL) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home)
    }

    private func write(_ file: URL, _ lines: [String]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
    }

    @discardableResult
    private func append(_ file: URL, _ lines: [String]) throws -> Int {
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        return data.count
    }

    private func truncate(_ file: URL, to length: Int) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(length))
    }

    private func size(_ file: URL) throws -> Int {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
    }

    private func setModified(_ file: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
    }

    private func claude(_ id: String, time: String, output: Int) -> String {
        """
        {"type":"assistant","timestamp":"2026-09-12T\(time).000Z","uuid":"uuid-\(id)","perTurnEffort":"medium","effort":"high","message":{"id":"\(id)","model":"claude-fable-5-1","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":\(output)},"content":[{"type":"text","text":"synthetic ignored content"}]}}
        """
    }

    private func codex(_ id: String, turn: String = "unknown", time: String, tokens: Int) -> String {
        """
        {"type":"token_usage_record","timestamp":"2026-09-12T\(time)Z","payload":{"turn_id":"\(turn)","response_id":"\(id)","usage":{"total_tokens":\(tokens)}}}
        """
    }

    private func turnContext(_ turn: String, effort: String) -> String {
        """
        {"type":"turn_context","payload":{"turn_id":"\(turn)","model":"gpt-6-astra","effort":"\(effort)"}}
        """
    }
}

private enum ReferenceScanners {
    private static let usageKeys = [
        "input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens",
    ]

    static func history(projectsRoot: URL, days: Int, now: Date, calendar: Calendar = .current) throws
        -> [ModelTokenBucket]
    {
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(days - 1), to: now)!)
        var messages: [String: (date: Date, model: String, tokens: Int)] = [:]
        for file in try files(under: projectsRoot) where try modified(file) >= start {
            for object in try lines(file) {
                guard object["type"] as? String == "assistant", let message = object["message"] as? [String: Any],
                    let usage = message["usage"] as? [String: Any], let timestamp = object["timestamp"] as? String,
                    let date = parse(timestamp), date >= start, date <= now.addingTimeInterval(300),
                    let id = message["id"] as? String ?? object["uuid"] as? String
                else { continue }
                let tokens = total(usage)
                guard tokens > 0 else { continue }
                let raw = message["model"] as? String
                let model = raw.map { $0.isEmpty || $0.hasPrefix("<") ? "unknown" : $0 } ?? "unknown"
                if let current = messages[id], current.tokens >= tokens { continue }
                messages[id] = (date, model, tokens)
            }
        }
        var totals: [String: ModelTokenBucket] = [:]
        for message in messages.values {
            let hour = Date(timeIntervalSince1970: (message.date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
            let key = "\(message.model)-\(hour.timeIntervalSince1970)"
            totals[key] = ModelTokenBucket(
                day: day(message.date, calendar), hourStart: hour, model: message.model,
                tokens: (totals[key]?.tokens ?? 0) + message.tokens)
        }
        return totals.values.sorted {
            $0.hourStart != $1.hourStart ? $0.hourStart < $1.hourStart : $0.model < $1.model
        }
    }

    static func effort(home: URL, lookbackDays: Int, now: Date, calendar: Calendar = .current) throws
        -> [EffortUsageRecord]
    {
        let cutoff = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1 - lookbackDays, to: now)!)
        let codexRoot = home.appending(path: ".codex/sessions")
        let recent = Set(recentDirectories(cutoff: cutoff, now: now))
        var records: [String: EffortUsageRecord] = [:]
        for (provider, root) in [(UsageProvider.codex, codexRoot), (.claude, home.appending(path: ".claude/projects"))]
        {
            for file in try files(under: root)
            where try modified(file) >= cutoff
                || recent.contains(file.deletingLastPathComponent().pathComponents.suffix(3).joined(separator: "/"))
            {
                var context: [String: Any]?
                for object in try lines(file) {
                    let type = object["type"] as? String
                    if provider == .codex, type == "turn_context" {
                        context = object["payload"] as? [String: Any]
                        continue
                    }
                    guard let timestamp = object["timestamp"] as? String, let date = parse(timestamp), date >= cutoff,
                        date <= now
                    else { continue }
                    let identifier: String?
                    let model: String?
                    let effort: String?
                    let tokens: Int?
                    if provider == .codex {
                        guard type == "token_usage_record", let payload = object["payload"] as? [String: Any] else {
                            continue
                        }
                        identifier = payload["response_id"] as? String
                        let turn = context?["turn_id"] as? String
                        let matching = turn != nil && turn == payload["turn_id"] as? String ? context : nil
                        model = matching?["model"] as? String
                        effort = matching?["effort"] as? String
                        tokens = (payload["usage"] as? [String: Any])?["total_tokens"] as? Int
                    } else {
                        guard type == "assistant", let message = object["message"] as? [String: Any] else { continue }
                        identifier = message["id"] as? String
                        model = message["model"] as? String
                        effort = object["perTurnEffort"] as? String ?? object["effort"] as? String
                        tokens = (message["usage"] as? [String: Any]).map(total)
                    }
                    guard let identifier, !identifier.isEmpty, let tokens, tokens > 0 else { continue }
                    let id = SHA256.hash(data: Data("\(provider.rawValue):\(identifier)".utf8))
                        .map { String(format: "%02x", $0) }.joined()
                    let record = EffortUsageRecord(
                        id: id, provider: provider, recordedAt: date, day: day(date, calendar),
                        model: normalizedModel(model), effort: normalizedEffort(effort), tokens: tokens)
                    records[id] = merge(records[id], record)
                }
            }
        }
        return records.values.sorted { $0.recordedAt == $1.recordedAt ? $0.id < $1.id : $0.recordedAt < $1.recordedAt }
    }

    private static func merge(_ existing: EffortUsageRecord?, _ incoming: EffortUsageRecord) -> EffortUsageRecord {
        guard let existing else { return incoming }
        let earliest = existing.recordedAt <= incoming.recordedAt ? existing : incoming
        return EffortUsageRecord(
            id: existing.id, provider: existing.provider, recordedAt: earliest.recordedAt, day: earliest.day,
            model: existing.model == "unknown" ? incoming.model : existing.model,
            effort: existing.effort == "unknown" ? incoming.effort : existing.effort,
            tokens: max(existing.tokens, incoming.tokens))
    }

    private static func normalizedModel(_ raw: String?) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard let raw, !raw.isEmpty, raw.count <= 100, raw.unicodeScalars.allSatisfy(allowed.contains) else {
            return "unknown"
        }
        return raw
    }

    private static func normalizedEffort(_ raw: String?) -> String {
        let value = raw?.lowercased() ?? "unknown"
        return ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra", "auto"].contains(value)
            ? value : "unknown"
    }

    private static func recentDirectories(cutoff: Date, now: Date) -> [String] {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var date = utc.startOfDay(for: cutoff.addingTimeInterval(-86_400))
        var directories: [String] = []
        while date <= now {
            let components = utc.dateComponents([.year, .month, .day], from: date)
            directories.append(String(format: "%04d/%02d/%02d", components.year!, components.month!, components.day!))
            date = date.addingTimeInterval(86_400)
        }
        return directories
    }

    private static func total(_ usage: [String: Any]) -> Int {
        usageKeys.reduce(0) { $0 + max(usage[$1] as? Int ?? 0, 0) }
    }

    private static func files(under root: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter {
            $0.pathExtension == "jsonl" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
    }

    private static func modified(_ file: URL) throws -> Date {
        try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
    }

    private static func lines(_ file: URL) throws -> [[String: Any]] {
        try Data(contentsOf: file).split(separator: 0x0A).compactMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        }
    }

    private static func parse(_ timestamp: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
    }

    private static func day(_ date: Date, _ calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
