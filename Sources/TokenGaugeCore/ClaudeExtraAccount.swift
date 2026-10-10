import Foundation

public struct ClaudeExtraAccount: Codable, Equatable, Identifiable, Sendable {
    public enum Tint: String, Codable, CaseIterable, Sendable {
        case claude, violet, blue, green
    }

    public enum Icon: String, Codable, CaseIterable, Sendable {
        case dot, balloon, briefcase, house, person, building
    }

    public var id: UUID
    public var name: String
    public var location: String
    public var tint: Tint
    public var icon: Icon
    public var showsInMenuBar: Bool

    public init(
        id: UUID = UUID(), name: String, location: String, tint: Tint = .claude, icon: Icon = .dot,
        showsInMenuBar: Bool = false
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.tint = tint
        self.icon = icon
        self.showsInMenuBar = showsInMenuBar
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        location = try container.decode(String.self, forKey: .location)
        tint = try container.decodeIfPresent(Tint.self, forKey: .tint) ?? .claude
        icon = try container.decodeIfPresent(Icon.self, forKey: .icon) ?? .dot
        showsInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showsInMenuBar) ?? false
    }
}

// "~/.claude-side" reads a config dir on this Mac; "work-mac:~/.claude-work" reads one over ssh.
public struct ClaudeAccountLocation: Equatable, Sendable {
    public let host: String?
    public let directory: String

    public static func parse(_ text: String) -> ClaudeAccountLocation? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        var host: String?
        var directory = trimmed
        if let colon = trimmed.firstIndex(of: ":"), !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~") {
            host = String(trimmed[..<colon])
            directory = String(trimmed[trimmed.index(after: colon)...])
        }
        if let host, host.isEmpty || host.hasPrefix("-") || !host.allSatisfy(isHostCharacter) { return nil }
        guard directory.hasPrefix("/") || directory == "~" || directory.hasPrefix("~/"),
            !directory.contains(where: { $0 == "'" || $0.isNewline })
        else { return nil }
        return ClaudeAccountLocation(host: host, directory: directory)
    }

    private static func isHostCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || "._-@".contains(character))
    }

    public var processArguments: (executable: String, arguments: [String]) {
        guard let host else { return ("/bin/sh", ["-c", Self.script, "sh", directory]) }
        let command = "/bin/sh -c \(Self.quoted(Self.script)) sh \(Self.quoted(directory))"
        return ("/usr/bin/ssh", ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-T", host, command])
    }

    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // Runs where the login lives, so the token never leaves that Mac: the credentials file
    // first, then the Keychain item Claude Code names after the config dir.
    static let script = #"""
        d="$1"
        case "$d" in "~") d="$HOME" ;; "~/"*) d="$HOME/${d#??}" ;; esac
        j=""
        if [ -f "$d/.credentials.json" ]; then j=$(cat "$d/.credentials.json" 2>/dev/null); fi
        t=$(printf %s "$j" | plutil -extract claudeAiOauth.accessToken raw -o - - 2>/dev/null)
        if [ -z "$t" ]; then
          s="Claude Code-credentials"
          [ "$d" = "$HOME/.claude" ] || s="$s-$(printf %s "$d" | shasum -a 256 | cut -c1-8)"
          j=$(security find-generic-password -a "$(id -un)" -s "$s" -w 2>/dev/null)
          t=$(printf %s "$j" | plutil -extract claudeAiOauth.accessToken raw -o - - 2>/dev/null)
        fi
        [ -n "$t" ] || { printf 'TG_STATUS 401\n'; exit 0; }
        e=$(printf %s "$j" | plutil -extract claudeAiOauth.expiresAt raw -o - - 2>/dev/null)
        if [ -n "$e" ] && [ "$e" -le "$(date +%s)000" ] 2>/dev/null; then printf 'TG_STATUS expired\n'; exit 0; fi
        printf 'Authorization: Bearer %s\n' "$t" | curl -s -m 10 -H @- -H 'anthropic-beta: oauth-2025-04-20' -w '\nTG_STATUS %{http_code} %header{retry-after}\n' https://api.anthropic.com/api/oauth/usage
        """#
}

public enum ClaudeExtraAccountResult: Equatable, Sendable {
    case windows([QuotaWindow])
    case status(Int)
    case rateLimited(retryAfter: TimeInterval?)
    case expired
    case unreachable
}

public enum ClaudeExtraAccountParser {
    public static func parse(_ output: Data?) -> ClaudeExtraAccountResult {
        guard let output, let text = String(data: output, encoding: .utf8),
            let marker = text.range(of: "TG_STATUS ", options: .backwards),
            case let fields = text[marker.upperBound...].split(whereSeparator: \.isWhitespace),
            let code = fields.first
        else { return .unreachable }
        if code == "expired" { return .expired }
        guard let status = Int(code) else { return .unreachable }
        if status == 429 {
            return .rateLimited(retryAfter: fields.dropFirst().first.flatMap { Int($0) }.map(TimeInterval.init))
        }
        guard status == 200 else { return .status(status) }
        let body = Data(text[..<marker.lowerBound].utf8)
        switch try? ClaudeAccountUsageParser.parseLimits(body) {
        case .windows(let windows)?: return .windows(windows)
        case .empty?: return .windows([])
        case nil: return .status(0)
        }
    }
}
