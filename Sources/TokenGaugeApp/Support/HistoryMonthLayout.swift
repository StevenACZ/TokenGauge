import Foundation

struct HistoryMonthLayout {
    struct Section {
        let date: Date
        let originX: CGFloat
        let width: CGFloat
        let indices: Range<Int>
        let leadingDays: Int
    }
    let sections: [Section]
    let gridWidth: CGFloat
    private let cells: [CGRect]

    init(days: [HistoryCalendarDay], calendar: Calendar = .current) {
        var sections: [Section] = []
        var cells: [CGRect] = []
        var start = 0
        var origin: CGFloat = 0
        while start < days.count {
            let date = days[start].date
            var end = start + 1
            while end < days.count, calendar.isDate(days[end].date, equalTo: date, toGranularity: .month) { end += 1 }
            let leading = (calendar.component(.weekday, from: date) + 5) % 7
            let columns = (leading + end - start + 6) / 7
            let width = Theme.Layout.historyMonthWidth
            let columnStep = columns > 1 ? (width - 9) / CGFloat(columns - 1) : 0
            sections.append(
                Section(date: date, originX: origin, width: width, indices: start..<end, leadingDays: leading))
            cells += (start..<end).map { index in
                let position = leading + index - start
                return CGRect(
                    x: origin + CGFloat(position / 7) * columnStep,
                    y: Theme.Layout.historyCalendarGridTop + CGFloat(position % 7) * 12, width: 9, height: 9)
            }
            origin += width + Theme.Layout.historyMonthGap
            start = end
        }
        self.sections = sections
        gridWidth = sections.last.map { $0.originX + $0.width } ?? 0
        self.cells = cells
    }

    func cellRect(_ index: Int) -> CGRect { cells.indices.contains(index) ? cells[index] : .zero }
    func index(at point: CGPoint) -> Int? { cells.firstIndex { $0.contains(point) } }
}
