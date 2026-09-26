import Foundation

struct EffortTranscriptMetadata: Decodable {
    let type: String?
    let timestamp: String?
    let uuid: String?
    let subtype: String?
    let durationMs: Int?
    let isSidechain: Bool?
    let perTurnEffort: String?
    let effort: String?
    let payload: Payload?
    let message: Message?

    struct Payload: Decodable {
        let type: String?
        let turn_id: String?
        let duration_ms: Int?
        let source: Source?
        let response_id: String?
        let model: String?
        let effort: String?
        let usage: Usage?
    }

    struct Message: Decodable {
        let id: String?
        let model: String?
        let usage: Usage?
    }

    struct Usage: Decodable {
        let total_tokens: Int?
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
        let cached_input_tokens: Int?

        var claudeTotal: Int? {
            var total = 0
            for count in [input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens] {
                let (sum, overflow) = total.addingReportingOverflow(max(0, count ?? 0))
                guard !overflow else { return nil }
                total = sum
            }
            return total
        }
    }

    struct Source: Decodable {
        let isSubagent: Bool

        private enum CodingKeys: String, CodingKey { case subagent }

        init(from decoder: Decoder) throws {
            if let value = try? decoder.singleValueContainer().decode(String.self) {
                isSubagent = value == "subagent"
            } else {
                isSubagent = (try? decoder.container(keyedBy: CodingKeys.self).contains(.subagent)) == true
            }
        }
    }

    struct SkillCalls: Decodable {
        let message: Message?

        struct Message: Decodable {
            let id: String?
            let content: [Item]?
        }

        struct Item: Decodable {
            let type: String?
            let id: String?
            let name: String?
            let skill: String?

            private enum CodingKeys: String, CodingKey { case type, id, name, input }
            private enum InputKeys: String, CodingKey { case skill }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                type = try? container.decode(String.self, forKey: .type)
                id = try? container.decode(String.self, forKey: .id)
                name = try? container.decode(String.self, forKey: .name)
                skill = try? container.nestedContainer(keyedBy: InputKeys.self, forKey: .input).decode(
                    String.self, forKey: .skill)
            }
        }
    }

    struct ToolCall: Decodable {
        let payload: Payload?

        struct Payload: Decodable {
            let arguments: String?
            let input: String?
        }
    }

    private static let efforts: Set<String> = [
        "none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra", "auto",
    ]
    private static let modelCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")

    static func normalizedEffort(_ raw: String?) -> String {
        let value = raw?.lowercased() ?? "unknown"
        return efforts.contains(value) ? value : "unknown"
    }

    static func normalizedModel(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty, raw.count <= 100, raw.unicodeScalars.allSatisfy(modelCharacters.contains)
        else { return "unknown" }
        return raw
    }
}
