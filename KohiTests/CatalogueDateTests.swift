import Foundation
import Testing
@testable import Kohi

struct CatalogueDateTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 16))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    @Test func todayIsJustNow() {
        #expect(CatalogueDate.happened(now, now: now, calendar: calendar) == "just now")
        #expect(CatalogueDate.happened(day(0), now: now, calendar: calendar) == "just now")
    }

    @Test func oneDayAgoIsYesterday() {
        #expect(CatalogueDate.happened(day(-1), now: now, calendar: calendar) == "yesterday")
    }

    @Test func twoToFiveDaysAreACount() {
        #expect(CatalogueDate.happened(day(-2), now: now, calendar: calendar) == "2 days")
        #expect(CatalogueDate.happened(day(-5), now: now, calendar: calendar) == "5 days")
    }

    @Test func sixDaysAndOlderAreADate() {
        let english = Locale(identifier: "en_GB")
        #expect(CatalogueDate.happened(day(-6), now: now, calendar: calendar, locale: english) == "11 Sep")
        let lastYear = calendar.date(from: DateComponents(year: 2025, month: 8, day: 25))!
        #expect(CatalogueDate.happened(lastYear, now: now, calendar: calendar, locale: english) == "25 Aug 2025")
    }
}
