import Foundation

/// When something happened, in one voice everywhere a brew, a recipe or a
/// sync is dated. Roast freshness (`23 d`) is a different question and stays
/// next to the roast date.
///
/// Same day → `just now`. Yesterday → `yesterday`. Two to five days →
/// `3 days`. Older → the calendar date.
nonisolated enum CatalogueDate {
    static let recentDays = 5

    static func happened(
        _ date: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        if days <= 0 { return "just now" }
        if days == 1 { return "yesterday" }
        if days <= recentDays { return "\(days) days" }
        let style: Date.FormatStyle = calendar.component(.year, from: date)
            == calendar.component(.year, from: now)
            ? .dateTime.day().month(.abbreviated)
            : .dateTime.day().month(.abbreviated).year()
        return date.formatted(style.locale(locale))
    }
}
