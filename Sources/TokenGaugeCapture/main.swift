import Foundation
import TokenGaugeCore

@main
enum TokenGaugeCapture {
    static func main() throws {
        let arguments = Set(CommandLine.arguments.dropFirst())
        if arguments.contains("--collect") {
            let scan = try TranscriptScanner.scan(stateURL: TranscriptScanner.stateURL())
            let recorded = (try? UsageHistoryStore.recordEffort(scan.effortRecords)) != nil
            try emit(CaptureCollection(buckets: scan.buckets, effortRecords: recorded ? scan.effortRecords.count : nil))
            return
        }
        let recordEffort = arguments.contains("--record-effort-history")
        if recordEffort || arguments.contains("--effort-history") {
            do {
                let records = try TranscriptScanner.scan(stateURL: TranscriptScanner.stateURL()).effortRecords
                if recordEffort {
                    try UsageHistoryStore.recordEffort(records)
                    try emit(["records": records.count])
                } else {
                    try emit(records)
                }
            } catch {
                exit(1)
            }
            return
        }
        if arguments.contains("--history") {
            try emit(try TranscriptScanner.scan(stateURL: TranscriptScanner.stateURL()).buckets)
            return
        }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard
            let snapshot = try? ClaudeUsageParser.capture(
                from: data, accountFingerprint: ClaudeAccountIdentityReader.current()?.fingerprint)
        else { return }
        try SecureMetricStore.write(snapshot, to: UsagePaths.claudeCapture())
    }

    private static func emit<T: Encodable>(_ value: T) throws {
        FileHandle.standardOutput.write(try JSONEncoder().encode(value))
    }
}
