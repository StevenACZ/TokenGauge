import Foundation

enum ActivityUsageScanner {
    private static let readCommands: Set<String> = ["sed", "cat", "head", "nl", "less", "bat", "tail"]
    private static let commandBoundaries = CharacterSet(charactersIn: "\"\n;|&(`{")
    private static let skillPath = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9._-])skills/([a-z0-9][a-z0-9._-]{0,63})/SKILL\.md"#)

    static func claude(
        _ metadata: EffortTranscriptMetadata, line: Data, at date: Date, subagent: Bool, parser: TranscriptLineParser
    ) -> [ActivityEntry] {
        let time = date.timeIntervalSince1970
        if metadata.type == "system", metadata.subtype == "turn_duration" {
            guard !subagent, metadata.isSidechain != true, let uuid = metadata.uuid, !uuid.isEmpty,
                let duration = metadata.durationMs, duration >= 0
            else { return [] }
            return [ActivityEntry(id: hash(.claude, "turn:\(uuid)"), at: time, kind: .turn, key: "", value: duration)]
        }
        guard metadata.type == "assistant", let message = parser.skillCalls(line)?.message,
            let messageID = message.id, !messageID.isEmpty
        else { return [] }
        return (message.content ?? []).compactMap { item in
            guard item.type == "tool_use", item.name == "Skill", let id = item.id, !id.isEmpty,
                let skill = item.skill, ActivityUsageRecord.isSkillName(skill)
            else { return nil }
            return ActivityEntry(
                id: hash(.claude, "skill:\(messageID):\(id)"), at: time, kind: .skill, key: skill, value: 1)
        }
    }

    static func codex(
        _ metadata: EffortTranscriptMetadata, line: Data, at date: Date, rollout: String, subagent: Bool,
        parser: TranscriptLineParser
    ) -> [ActivityEntry] {
        let time = date.timeIntervalSince1970
        guard let payload = metadata.payload else { return [] }
        switch (metadata.type, payload.type) {
        case ("event_msg", "task_complete"):
            guard !subagent, let turn = payload.turn_id, !turn.isEmpty, let duration = payload.duration_ms,
                duration >= 0
            else { return [] }
            return [ActivityEntry(id: hash(.codex, "turn:\(turn)"), at: time, kind: .turn, key: "", value: duration)]
        case ("response_item", "function_call"), ("response_item", "custom_tool_call"):
            guard let call = parser.toolCall(line)?.payload else { return [] }
            return readSkills(in: call.arguments ?? call.input ?? "").sorted().map { skill in
                ActivityEntry(
                    id: hash(.codex, "skill:\(rollout):\(skill)"), at: time, kind: .skill, key: skill, value: 1)
            }
        default:
            return []
        }
    }

    static func readSkills(in command: String) -> Set<String> {
        guard command.contains("SKILL.md") else { return [] }
        let text = command.replacingOccurrences(of: "\\n", with: "\n") as NSString
        var skills: Set<String> = []
        for match in skillPath.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
            let prefix = text.substring(to: match.range.location)
            let start = prefix.rangeOfCharacter(from: commandBoundaries, options: .backwards)?.upperBound
            let segment = start.map { prefix[$0...] } ?? prefix[...]
            guard let program = segment.split(whereSeparator: \.isWhitespace).first?.split(separator: "/").last,
                readCommands.contains(String(program))
            else { continue }
            skills.insert(text.substring(with: match.range(at: 1)))
        }
        return skills
    }

    static func records(
        _ entries: some Sequence<(provider: UsageProvider, entry: ActivityEntry)>, cutoff: Date, now: Date,
        calendar: Calendar
    ) -> [ActivityUsageRecord] {
        let earliest = cutoff.timeIntervalSince1970
        let latest = now.timeIntervalSince1970
        return entries.compactMap { provider, entry -> ActivityUsageRecord? in
            guard entry.at >= earliest, entry.at <= latest else { return nil }
            let recordedAt = Date(timeIntervalSince1970: entry.at)
            return ActivityUsageRecord(
                id: entry.id, provider: provider, recordedAt: recordedAt,
                day: TranscriptScanner.dayString(recordedAt, calendar: calendar), kind: entry.kind, key: entry.key,
                value: entry.value)
        }.sorted { $0.recordedAt == $1.recordedAt ? $0.id < $1.id : $0.recordedAt < $1.recordedAt }
    }

    private static func hash(_ provider: UsageProvider, _ identifier: String) -> String {
        EffortUsageScanner.hash(provider: provider, identifier: identifier)
    }
}
