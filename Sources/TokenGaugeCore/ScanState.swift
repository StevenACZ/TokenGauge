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
        public let bytesRead: Int
    }

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
            return Result(buckets: [], effortRecords: [], bytesRead: 0)
        }
        let previous = stateURL.flatMap { ScanState.load(from: $0, windowStart: readStart) }
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
        for root in roots {
            for (file, attributes) in candidateFiles(root: root.url, wanted: root.wanted) {
                let key = file.path
                let scanned = try scanFile(
                    file, attributes: attributes, provider: root.provider, previous: previous?.files[key],
                    parser: parser, prune: readStart)
                bytesRead += scanned.bytesRead
                state.files[key] = scanned.file
            }
        }

        let historyCutoff = historyStart?.timeIntervalSince1970
        let effortCutoff = effortStart?.timeIntervalSince1970
        var historyEntries: [String: ScanEntry] = [:]
        var effortEntries: [String: (provider: UsageProvider, entry: ScanEntry)] = [:]
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
        }

        if let stateURL {
            try? SecureMetricStore.write(state, to: stateURL)
        }
        return Result(
            buckets: historyStart.map {
                ClaudeHistoryScanner.buckets(historyEntries.values, start: $0, now: now, calendar: calendar)
            } ?? [],
            effortRecords: effortStart.map {
                EffortUsageScanner.records(effortEntries.values, cutoff: $0, now: now, calendar: calendar)
            } ?? [],
            bytesRead: bytesRead)
    }

    private static func dayDirectory(_ url: URL) -> String {
        url.pathComponents.suffix(3).joined(separator: "/")
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
        var entries: [String: ScanEntry] = [:]
        var context: CodexTurnContext?
        var offset = 0
        if let reusable, attributes.size > reusable.size, attributes.modified >= reusable.modified {
            entries = Dictionary(reusable.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            context = reusable.context
            offset = reusable.offset
        }
        let handler: (Data) -> Void = { line in
            autoreleasepool {
                guard let metadata = parser.metadata(line) else { return }
                let entry: ScanEntry?
                switch provider {
                case .claude:
                    guard let date = parser.date(metadata.timestamp) else { return }
                    entry = ClaudeHistoryScanner.entry(from: metadata, at: date)
                case .codex:
                    if metadata.type == "turn_context" {
                        context = metadata.payload.map(CodexTurnContext.init)
                        return
                    }
                    guard let date = parser.date(metadata.timestamp) else { return }
                    entry = EffortUsageScanner.entry(from: metadata, at: date, context: context)
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
            context = nil
            progress = try JSONLReader.read(url, lineHandler: handler)
        }
        let kept = entries.values.filter { $0.peakAt >= prune }.sorted {
            $0.firstAt == $1.firstAt ? $0.id < $1.id : $0.firstAt < $1.firstAt
        }
        let file = ScanFile(
            provider: provider, size: attributes.size, modified: attributes.modified, created: attributes.created,
            offset: progress.committedOffset, context: context, entries: kept)
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

    func date(_ timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        return fractional.date(from: timestamp) ?? standard.date(from: timestamp)
    }
}

struct ScanState: Codable {
    static let currentVersion = 1

    var version: Int
    var windowStart: TimeInterval
    var files: [String: ScanFile]

    static func load(from url: URL, windowStart: TimeInterval) -> ScanState? {
        guard let state = try? SecureMetricStore.read(ScanState.self, from: url), state.version == currentVersion,
            state.windowStart <= windowStart
        else { return nil }
        return state
    }
}

struct ScanFile: Codable {
    var provider: UsageProvider
    var size: Int
    var modified: TimeInterval
    var created: TimeInterval
    var offset: Int
    var context: CodexTurnContext?
    var entries: [ScanEntry]
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
    }
}
