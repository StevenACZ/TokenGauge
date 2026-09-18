import Foundation

struct EffortTranscriptMetadata: Decodable {
    let type: String?
    let timestamp: String?
    let uuid: String?
    let perTurnEffort: String?
    let effort: String?
    let payload: Payload?
    let message: Message?

    struct Payload: Decodable {
        let turn_id: String?
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
