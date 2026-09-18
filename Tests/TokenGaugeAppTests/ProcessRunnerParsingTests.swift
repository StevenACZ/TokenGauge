import Foundation
import XCTest

@testable import TokenGaugeApp

final class ProcessRunnerParsingTests: XCTestCase {
    func testResponseIdentifiersParseOnlyNewBytes() {
        let lines = (1...4).map { "{\"id\":\($0),\"result\":{}}\n" }
        var output = Data()
        var scanned = 0
        var identifiers: Set<Int> = []
        var scannedPerChunk: [Int] = []

        for line in lines {
            let before = scanned
            output.append(Data(line.utf8))
            identifiers.formUnion(ProcessRunner.responseIdentifiers(in: output, from: &scanned))
            scannedPerChunk.append(scanned - before)
        }

        XCTAssertEqual(identifiers, [1, 2, 3, 4])
        XCTAssertEqual(scannedPerChunk, lines.map(\.utf8.count))
        XCTAssertEqual(scanned, output.count)
    }

    func testIncompleteLineIsScannedOnlyOnceItIsComplete() {
        var output = Data("{\"id\":7,\"res".utf8)
        var scanned = 0

        XCTAssertTrue(ProcessRunner.responseIdentifiers(in: output, from: &scanned).isEmpty)
        XCTAssertEqual(scanned, 0)

        output.append(Data("ult\":{}}\n".utf8))
        XCTAssertEqual(ProcessRunner.responseIdentifiers(in: output, from: &scanned), [7])
        XCTAssertEqual(scanned, output.count)
    }

    func testFinalLineWithoutNewlineIsScannedAtEndOfOutput() {
        let output = Data("{\"id\":2}\n{\"id\":3}".utf8)
        var scanned = 0

        XCTAssertEqual(ProcessRunner.responseIdentifiers(in: output, from: &scanned), [2])
        XCTAssertEqual(ProcessRunner.responseIdentifiers(in: output, from: &scanned, includingTail: true), [3])
        XCTAssertEqual(scanned, output.count)
    }
}
