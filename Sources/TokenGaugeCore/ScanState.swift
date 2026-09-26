import Foundation

public struct CaptureCollection: Codable, Sendable {
    public let buckets: [ModelTokenBucket]
    public let effortRecords: Int?

    public init(buckets: [ModelTokenBucket], effortRecords: Int?) {
        self.buckets = buckets
        self.effortRecords = effortRecords
    }
}

public enum TranscriptScanner {
    public struct Result: Sendable {
        public let buckets: [ModelTokenBucket]
        public let effortRecords: [EffortUsageRecord]
        public let activityRecords: [ActivityUsageRecord]
        public let bytesRead: Int
    }

    static let checkpointInterval: TimeInterval = 5

    public static func stateURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        UsagePaths.supportDirectory(homeDirectory: homeDirectory).appending(path: "scan-state.json")
    }

    public static func scan(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        stateURL: URL? = nil,
        now: Date = Date(),
        calendar: Calendar = .current,
        historyDays: Int = 8,
        effortDays: Int = 7
    ) throws -> Result {
        let claude = homeDirectory.appending(path: ".claude/projects")
        let codex = homeDirectory.appending(path: ".codex/sessions")
        return try scan(
            claudeProjects: EffortUsageScanner.safePath(claude, home: homeDirectory) ? claude : nil,
            codexSessions: EffortUsageScanner.safePath(codex, home: homeDirectory) ? codex : nil,
            stateURL: stateURL, now: now, calendar: calendar, historyDays: historyDays, effortDays: effortDays)
    }

    public static func scan(
        claudeProjects: URL?,
        codexSessions: URL?,
        stateURL: URL?,
        now: Date = Date(),
        calendar: Calendar = .current,
        historyDays: Int = 8,
        effortDays: Int = 7
    ) throws -> Result {
        let historyStart = windowStart(days: historyDays, now: now, calendar: calendar)
        let effortStart = windowStart(days: effortDays, now: now, calendar: calendar)
        guard let readStart = [historyStart, effortStart].compactMap({ $0?.timeIntervalSince1970 }).min() else {
            return Result(buckets: [], effortRecords: [], activityRecords: [], bytesRead: 0)
        }
        let loaded = stateURL.flatMap { ScanState.load(from: $0, windowStart: readStart) }
        let previous = loaded?.state
        var state = ScanState(version: ScanState.currentVersion, windowStart: readStart, files: [:])
        var recentCodexDirectories: Set<String> = []
        var roots: [(provider: UsageProvider, url: URL, wanted: (URL, TimeInterval) -> Bool)] = []
        if let claudeProjects {
            roots.append((.claude, claudeProjects, { _, modified in modified >= readStart }))
        }
        if let codexSessions, let effortStart {
            let cutoff = effortStart.timeIntervalSince1970
            recentCodexDirectories = Set(
                EffortUsageScanner.codexDirectories(root: codexSessions, cutoff: effortStart, now: now).map(
                    dayDirectory))
            roots.append(
                (
                    .codex, codexSessions,
                    { file, modified in
                        modified >= cutoff
                            || recentCodexDirectories.contains(dayDirectory(file.deletingLastPathComponent()))
                    }
                ))
        }

        let parser = TranscriptLineParser()
        var bytesRead = 0
        var written = loaded?.encoded
        var checkpointed = ProcessInfo.processInfo.systemUptime
        func checkpoint() {
            guard let stateURL else { return }
            var partial = state
            partial.files.merge(previous?.files ?? [:]) { current, _ in current }
            persist(partial, to: stateURL, encoded: &written)
            checkpointed = ProcessInfo.processInfo.systemUptime
        }
        for root in roots {
            for (file, attributes) in candidateFiles(root: root.url, wanted: root.wanted) {
                let key = file.path
                let scanned = try scanFile(
                    file, attributes: attributes, provider: root.provider, previous: previous?.files[key],
                    parser: parser, prune: readStart)
                bytesRead += scanned.bytesRead
                state.files[key] = scanned.file
                if ProcessInfo.processInfo.systemUptime - checkpointed >= checkpointInterval { checkpoint() }
            }
            checkpoint()
        }

        let historyCutoff = historyStart?.timeIntervalSince1970
        let effortCutoff = effortStart?.timeIntervalSince1970
        var historyEntries: [String: ScanEntry] = [:]
        var effortEntries: [String: (provider: UsageProvider, entry: ScanEntry)] = [:]
        var activityEntries: [String: (provider: UsageProvider, entry: ActivityEntry)] = [:]
        for key in state.files.keys.sorted() {
            guard let file = state.files[key] else { continue }
            let recent = recentCodexDirectories.contains(dayDirectory(URL(filePath: key).deletingLastPathComponent()))
            let includeHistory = historyCutoff.map { file.provider == .claude && file.modified >= $0 } ?? false
            let includeEffort = effortCutoff.map { file.modified >= $0 || (file.provider == .codex && recent) } ?? false
            guard includeHistory || includeEffort else { continue }
            for entry in file.entries {
                if includeHistory {
                    historyEntries[entry.id] = historyEntries[entry.id]?.merging(entry) ?? entry
                }
                if includeEffort {
                    let merged = effortEntries[entry.id]?.entry.merging(entry) ?? entry
                    effortEntries[entry.id] = (file.provider, merged)
                }
            }
            guard includeEffort else { continue }
            for entry in file.activities {
                activityEntries[entry.id] = (file.provider, activityEntries[entry.id]?.entry.merging(entry) ?? entry)
            }
        }

        if let stateURL { persist(state, to: stateURL, encoded: &written) }
        return Result(
            buckets: historyStart.map {
                ClaudeHistoryScanner.buckets(historyEntries.values, start: $0, now: now, calendar: calendar)
            } ?? [],
            effortRecords: effortStart.map {
                EffortUsageScanner.records(effortEntries.values, cutoff: $0, now: now, calendar: calendar)
            } ?? [],
            activityRecords: effortStart.map {
                ActivityUsageScanner.records(activityEntries.values, cutoff: $0, now: now, calendar: calendar)
            } ?? [],
            bytesRead: bytesRead)
    }

    private static func persist(_ state: ScanState, to url: URL, encoded: inout Data?) {
        guard let data = try? JSONEncoder.tokenGauge.encode(state), data != encoded else { return }
        try? SecureMetricStore.write(state, to: url)
        encoded = data
    }

    private static func dayDirectory(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func windowStart(days: Int, now: Date, calendar: Calendar) -> Date? {
        guard days > 0 else { return nil }
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1 - days, to: now) ?? now)
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey,
    ]

    private struct FileAttributes {
        let size: Int
        let modified: TimeInterval
        let created: TimeInterval
    }

    private static func candidateFiles(root: URL, wanted: (URL, TimeInterval) -> Bool) -> [(URL, FileAttributes)] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(resourceKeys), options: [.skipsHiddenFiles])
        else { return [] }
        var files: [(URL, FileAttributes)] = []
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: resourceKeys), values.isSymbolicLink != true else {
                enumerator.skipDescendants()
                continue
            }
            let modified = (values.contentModificationDate ?? .distantPast).timeIntervalSince1970
            guard values.isRegularFile == true, file.pathExtension == "jsonl", wanted(file, modified) else { continue }
            let created = (values.creationDate ?? .distantPast).timeIntervalSince1970
            files.append((file, FileAttributes(size: values.fileSize ?? 0, modified: modified, created: created)))
        }
        return files
    }

    private static func scanFile(
        _ url: URL, attributes: FileAttributes, provider: UsageProvider, previous: ScanFile?,
        parser: TranscriptLineParser, prune: TimeInterval
    ) throws -> (file: ScanFile, bytesRead: Int) {
        let reusable = previous.flatMap { $0.provider == provider && $0.created == attributes.created ? $0 : nil }
        if let reusable, reusable.size == attributes.size, reusable.modified == attributes.modified {
            return (reusable, 0)
        }
        let claudeSubagent = provider == .claude && url.pathComponents.contains("subagents")
        var entries: [String: ScanEntry] = [:]
        var activities: [String: ActivityEntry] = [:]
        var subagent = claudeSubagent
        var context: CodexTurnContext?
        var offset = 0
        if let reusable, attributes.size > reusable.size, attributes.modified >= reusable.modified,
            ((try? JSONLReader.anchor(url, endingAt: reusable.offset)) ?? nil) == reusable.anchor
        {
            entries = Dictionary(reusable.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            activities = Dictionary(reusable.activities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            subagent = reusable.subagent
            context = reusable.context
            offset = reusable.offset
        }
        let handler: (Data) -> Void = { line in
            autoreleasepool {
                guard let metadata = parser.metadata(line) else { return }
                let entry: ScanEntry?
                let found: [ActivityEntry]
                switch provider {
                case .claude:
                    guard let date = parser.date(metadata.timestamp) else { return }
                    found = ActivityUsageScanner.claude(
                        metadata, line: line, at: date, subagent: subagent, parser: parser)
                    entry = ClaudeHistoryScanner.entry(from: metadata, at: date)
                case .codex:
                    if metadata.type == "turn_context" {
                        context = metadata.payload.map(CodexTurnContext.init)
                        return
                    }
                    if metadata.type == "session_meta" {
                        subagent = metadata.payload?.source?.isSubagent == true
                        return
                    }
                    guard let date = parser.date(metadata.timestamp) else { return }
                    found = ActivityUsageScanner.codex(
                        metadata, line: line, at: date, rollout: url.lastPathComponent, subagent: subagent,
                        parser: parser)
                    entry = EffortUsageScanner.entry(from: metadata, at: date, context: context)
                }
                for activity in found {
                    activities[activity.id] = activities[activity.id]?.merging(activity) ?? activity
                }
                guard let entry else { return }
                entries[entry.id] = entries[entry.id]?.merging(entry) ?? entry
            }
        }
        let progress: JSONLReader.Progress
        do {
            progress = try JSONLReader.read(url, from: offset, lineHandler: handler)
        } catch JSONLReader.ReadError.offsetNotAtLineBoundary {
            entries = [:]
            activities = [:]
            subagent = claudeSubagent
            context = nil
            progress = try JSONLReader.read(url, lineHandler: handler)
        }
        let kept = entries.values.filter { $0.peakAt >= prune }.sorted {
            $0.firstAt == $1.firstAt ? $0.id < $1.id : $0.firstAt < $1.firstAt
        }
        let keptActivities = activities.values.filter { $0.at >= prune }.sorted {
            $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at
        }
        let file = ScanFile(
            provider: provider, size: attributes.size, modified: attributes.modified, created: attributes.created,
            offset: progress.committedOffset, anchor: try JSONLReader.anchor(url, endingAt: progress.committedOffset),
            context: context, entries: kept, subagent: subagent, activities: keptActivities)
        return (file, progress.bytesRead)
    }
}

struct TranscriptLineParser {
    private let decoder = JSONDecoder()
    private let fractional: ISO8601DateFormatter
    private let standard = ISO8601DateFormatter()

    init() {
        fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func metadata(_ line: Data) -> EffortTranscriptMetadata? {
        try? decoder.decode(EffortTranscriptMetadata.self, from: line)
    }

    func skillCalls(_ line: Data) -> EffortTranscriptMetadata.SkillCalls? {
        guard line.range(of: Self.skillMarker) != nil else { return nil }
        return try? decoder.decode(EffortTranscriptMetadata.SkillCalls.self, from: line)
    }

    func toolCall(_ line: Data) -> EffortTranscriptMetadata.ToolCall? {
        guard line.range(of: Self.skillFileMarker) != nil else { return nil }
        return try? decoder.decode(EffortTranscriptMetadata.ToolCall.self, from: line)
    }

    private static let skillMarker = Data("\"Skill\"".utf8)
    private static let skillFileMarker = Data("SKILL.md".utf8)

    func date(_ timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        return fractional.date(from: timestamp) ?? standard.date(from: timestamp)
    }
}

struct ScanState: Codable {
    static let currentVersion = 3

    var version: Int
    var windowStart: TimeInterval
    var files: [String: ScanFile]

    static func load(from url: URL, windowStart: TimeInterval) -> (state: ScanState, encoded: Data)? {
        guard let encoded = try? Data(contentsOf: url),
            let state = try? JSONDecoder.tokenGauge.decode(ScanState.self, from: encoded),
            state.version == currentVersion, state.windowStart <= windowStart
        else { return nil }
        return (state, encoded)
    }
}

struct ScanFile: Codable {
    var provider: UsageProvider
    var size: Int
    var modified: TimeInterval
    var created: TimeInterval
    var offset: Int
    var anchor: String?
    var context: CodexTurnContext?
    var entries: [ScanEntry]
    var subagent: Bool
    var activities: [ActivityEntry]
}

struct ActivityEntry: Codable, Equatable {
    var id: String
    var at: TimeInterval
    var kind: HistoryActivityKind
    var key: String
    var value: Int

    func merging(_ incoming: ActivityEntry) -> ActivityEntry {
        var merged = self
        merged.at = min(at, incoming.at)
        merged.value = max(value, incoming.value)
        return merged
    }
}

struct CodexTurnContext: Codable, Equatable {
    var turnID: String?
    var model: String
    var effort: String

    init(payload: EffortTranscriptMetadata.Payload) {
        turnID = payload.turn_id
        model = EffortTranscriptMetadata.normalizedModel(payload.model)
        effort = EffortTranscriptMetadata.normalizedEffort(payload.effort)
    }
}

struct ScanEntry: Equatable {
    var id: String
    var firstAt: TimeInterval
    var peakAt: TimeInterval
    var tokens: Int
    var model: String
    var effortModel: String
    var effort: String
    var eligible: Bool
    var cachedTokens: Int?

    func merging(_ incoming: ScanEntry) -> ScanEntry {
        var merged = self
        if incoming.tokens > tokens {
            merged.tokens = incoming.tokens
            merged.peakAt = incoming.peakAt
            merged.model = incoming.model
        }
        merged.firstAt = min(firstAt, incoming.firstAt)
        if effortModel == "unknown" { merged.effortModel = incoming.effortModel }
        if effort == "unknown" { merged.effort = incoming.effort }
        merged.eligible = eligible || incoming.eligible
        merged.cachedTokens = [cachedTokens, incoming.cachedTokens].compactMap { $0 }.max()
        return merged
    }
}

extension ScanEntry: Codable {
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        id = try container.decode(String.self)
        firstAt = try container.decode(TimeInterval.self)
        peakAt = try container.decode(TimeInterval.self)
        tokens = try container.decode(Int.self)
        model = try container.decode(String.self)
        effortModel = try container.decode(String.self)
        effort = try container.decode(String.self)
        eligible = try container.decode(Bool.self)
        cachedTokens = try container.decodeIfPresent(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(id)
        try container.encode(firstAt)
        try container.encode(peakAt)
        try container.encode(tokens)
        try container.encode(model)
        try container.encode(effortModel)
        try container.encode(effort)
        try container.encode(eligible)
        try container.encode(cachedTokens)
    }
}
