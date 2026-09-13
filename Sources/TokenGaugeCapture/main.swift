import Foundation
import TokenGaugeCore

@main
enum TokenGaugeCapture {
    static func main() throws {
        let recordEffort = CommandLine.arguments.contains("--record-effort-history")
        if recordEffort || CommandLine.arguments.contains("--effort-history") {
            do {
                let records = try EffortUsageScanner.scan()
                if recordEffort {
                    try UsageHistoryStore.recordEffort(records)
                    FileHandle.standardOutput.write(try JSONEncoder().encode(["records": records.count]))
                } else {
                    FileHandle.standardOutput.write(try JSONEncoder().encode(records))
                }
            } catch {
                exit(1)
            }
            return
        }
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
