import Foundation

public enum UsagePaths {
    public static func supportDirectory(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory.appending(path: "Library/Application Support/TokenGauge", directoryHint: .isDirectory)
    }

    public static func claudeCapture(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        supportDirectory(homeDirectory: homeDirectory).appending(path: "claude-usage.json")
    }

    public static func codexCache(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        supportDirectory(homeDirectory: homeDirectory).appending(path: "codex-usage.json")
    }

    public static func claudeAccountCache(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        supportDirectory(homeDirectory: homeDirectory).appending(path: "claude-account-usage.json")
    }

    public static func claudeProjects(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory.appending(path: ".claude/projects", directoryHint: .isDirectory)
    }
}
