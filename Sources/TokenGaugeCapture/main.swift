import Foundation
import TokenGaugeCore

@main
enum TokenGaugeCapture {
    static func main() throws {
        if CommandLine.arguments.contains("--history") {
            let usage = try ClaudeHistoryScanner.scan()
            FileHandle.standardOutput.write(try JSONEncoder().encode(usage))
            return
        }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let snapshot = try? ClaudeUsageParser.capture(from: data) else { return }
        try SecureMetricStore.write(snapshot, to: UsagePaths.claudeCapture())
    }
}
