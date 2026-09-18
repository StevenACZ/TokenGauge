import Foundation

enum Hex {
    private static let digits = Array("0123456789abcdef".utf8)

    static func string(_ bytes: some Sequence<UInt8>) -> String {
        String(decoding: bytes.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 15)]] }, as: UTF8.self)
    }
}
