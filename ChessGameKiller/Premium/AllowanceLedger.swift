import Foundation

/// Counts uses of the counted Premium features, per day or per week, on this device.
/// A new day (or week) starts the count again.
///
/// A use can carry a key, such as a game's id: using the same key again in the same period
/// is free, so opening one game's full Rewind twice in a day counts once.
struct AllowanceLedger {
    let defaults: UserDefaults
    var calendar: Calendar = .current

    static let keyPrefix = "premium.allowance."

    private struct Entry: Codable {
        var periodStart: Date
        var count: Int
        var keys: [String]
    }

    /// Uses so far in the period that holds `now`.
    func used(_ feature: PremiumFeature, allowance: PremiumFeature.Allowance, now: Date = .now) -> Int {
        current(feature, allowance: allowance, now: now).count
    }

    /// Uses left in the period; never below zero.
    func remaining(_ feature: PremiumFeature, allowance: PremiumFeature.Allowance, now: Date = .now) -> Int {
        max(0, allowance.uses - used(feature, allowance: allowance, now: now))
    }

    /// Whether this key was already used in the period, so using it again costs nothing.
    func alreadyUsed(_ feature: PremiumFeature, key: String, allowance: PremiumFeature.Allowance, now: Date = .now) -> Bool {
        current(feature, allowance: allowance, now: now).keys.contains(key)
    }

    /// Takes one use if there is one left. False when the allowance is spent.
    @discardableResult
    func take(_ feature: PremiumFeature, key: String? = nil, allowance: PremiumFeature.Allowance, now: Date = .now) -> Bool {
        var entry = current(feature, allowance: allowance, now: now)
        if let key, entry.keys.contains(key) { return true }
        guard entry.count < allowance.uses else { return false }
        entry.count += 1
        if let key { entry.keys.append(key) }
        save(entry, for: feature)
        return true
    }

    /// The first moment of the period that holds `date`.
    func periodStart(_ period: PremiumFeature.Allowance.Period, for date: Date) -> Date {
        switch period {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    /// Forgets every count (for tests and a fresh start).
    func reset() {
        for feature in PremiumFeature.allCases {
            defaults.removeObject(forKey: Self.keyPrefix + feature.rawValue)
        }
    }

    private func current(_ feature: PremiumFeature, allowance: PremiumFeature.Allowance, now: Date) -> Entry {
        let start = periodStart(allowance.period, for: now)
        guard let data = defaults.data(forKey: Self.keyPrefix + feature.rawValue),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.periodStart == start else {
            return Entry(periodStart: start, count: 0, keys: [])
        }
        return entry
    }

    private func save(_ entry: Entry, for feature: PremiumFeature) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        defaults.set(data, forKey: Self.keyPrefix + feature.rawValue)
    }
}
