enum StatsCard: String, CaseIterable {
    case forecast
    case today
    case daily
    case activity
    case models
    case efforts
    case skills

    static func decode(_ values: [String]?) -> Set<StatsCard> {
        Set((values ?? []).compactMap(StatsCard.init(rawValue:)))
    }
}
