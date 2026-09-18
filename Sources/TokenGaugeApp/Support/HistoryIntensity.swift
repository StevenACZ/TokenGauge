import Foundation

enum HistoryIntensity {
    static let opacities: [Double] = [0.30, 0.48, 0.66, 0.84, 1.0]
    static let minorityShare = 0.25

    static func thresholds(totals: [Int]) -> [Int] {
        let sorted = totals.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return [] }
        return [0.2, 0.4, 0.6, 0.8].map { quantile in
            sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * quantile))]
        }
    }

    static func level(total: Int, thresholds: [Int]) -> Int {
        thresholds.filter { total > $0 }.count
    }

    static func opacity(total: Int, thresholds: [Int]) -> Double {
        opacities[min(opacities.count - 1, level(total: total, thresholds: thresholds))]
    }
}
