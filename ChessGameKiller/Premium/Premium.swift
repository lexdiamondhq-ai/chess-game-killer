import Foundation
import Observation
import StoreKit

/// Whether the player has Premium, the plans on sale, and the free allowances.
///
/// Gates call `use(_:)` for a counted feature (it takes one use, or says the allowance is spent)
/// and `opens(_:)` for a locked one. When either says no, the screen shows the Premium offer.
///
/// Purchases go through StoreKit 2. In the Simulator, Xcode sells the plans from
/// Support/Premium.storekit, so buying can be tried before App Store Connect has them.
@MainActor
@Observable
final class Premium {
    static let shared = Premium.live()

    /// Remembered, so the app knows straight away at launch; StoreKit confirms it a moment later.
    nonisolated static let activeKey = "premium.active"

    private(set) var isPremium: Bool
    /// The plans as the App Store sells them, once loaded.
    private(set) var products: [PremiumPlan: Product] = [:]
    /// The plan being bought, while the App Store's sheet is up.
    private(set) var purchasing: PremiumPlan?
    private(set) var isRestoring = false
    /// Why the last purchase or restore didn't work, in plain words.
    var problem: String?
    /// Goes up with every use, so a screen showing what's left redraws.
    private(set) var uses = 0

    @ObservationIgnored let ledger: AllowanceLedger
    /// Everything open and uncounted: the tests, and screenshots that show a screen in full.
    @ObservationIgnored let unlimited: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(defaults: UserDefaults = .standard, isPremium: Bool? = nil, unlimited: Bool = false) {
        self.defaults = defaults
        self.ledger = AllowanceLedger(defaults: defaults)
        self.unlimited = unlimited
        self.isPremium = isPremium ?? defaults.bool(forKey: Self.activeKey)
    }

    /// The app's own: unlimited under XCTest (so tests and their pictures aren't counted),
    /// and Premium when CI launches with `-premium YES` for screenshots.
    static func live(_ defaults: UserDefaults = .standard) -> Premium {
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let forced = defaults.string(forKey: "premium").map { ["yes", "true", "1"].contains($0.lowercased()) }
        return Premium(defaults: defaults, isPremium: forced, unlimited: underTest)
    }

    // MARK: Allowances

    /// The allowance that applies to this player now. Nil: unlimited.
    func allowance(_ feature: PremiumFeature) -> PremiumFeature.Allowance? {
        if unlimited { return nil }
        return isPremium ? feature.premium : feature.free
    }

    /// Uses left now. Nil: unlimited. Zero for a locked feature without Premium.
    func remaining(_ feature: PremiumFeature) -> Int? {
        _ = uses
        if feature.isLocked { return opens(feature) ? nil : 0 }
        guard let allowance = allowance(feature) else { return nil }
        return ledger.remaining(feature, allowance: allowance)
    }

    /// Whether a counted feature can be used now, without taking a use.
    func canUse(_ feature: PremiumFeature, key: String? = nil) -> Bool {
        guard let allowance = allowance(feature) else { return opens(feature) || !feature.isLocked }
        if let key, ledger.alreadyUsed(feature, key: key, allowance: allowance) { return true }
        return ledger.remaining(feature, allowance: allowance) > 0
    }

    /// Takes one use of a counted feature. False when it's spent: show the offer instead.
    /// The same `key` again in the same period is free.
    @discardableResult
    func use(_ feature: PremiumFeature, key: String? = nil) -> Bool {
        if feature.isLocked { return opens(feature) }
        guard let allowance = allowance(feature) else { return true }
        let took = ledger.take(feature, key: key, allowance: allowance)
        if took { uses += 1 }
        return took
    }

    /// Gives back a use whose request failed, so a dropped connection never costs a free try.
    func giveBack(_ feature: PremiumFeature, key: String? = nil) {
        guard !feature.isLocked, let allowance = allowance(feature) else { return }
        ledger.giveBack(feature, key: key, allowance: allowance)
        uses += 1
    }

    /// How much of a counted allowance is used and when it comes back, for the limit card
    /// and the offer. Nil when there's no count to show (unlimited, or a locked feature).
    func usage(_ feature: PremiumFeature, now: Date = .now) -> PremiumUsage? {
        _ = uses
        guard !feature.isLocked, let allowance = allowance(feature) else { return nil }
        let used: Int = min(allowance.uses, ledger.used(feature, allowance: allowance, now: now))
        let back: Date = ledger.refreshDate(allowance.period, after: now)
        return PremiumUsage(used: used, of: allowance.uses, period: allowance.period, refreshes: back)
    }

    /// Whether a locked feature is open.
    func opens(_ feature: PremiumFeature) -> Bool {
        unlimited || isPremium || !feature.isLocked
    }

    // MARK: The App Store

    /// Loads the plans and the player's subscription, and listens for renewals and refunds.
    func start() {
        guard !started else { return }
        started = true
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refreshEntitlement()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    func loadProducts() async {
        do {
            let found = try await Product.products(for: PremiumPlan.allCases.map(\.rawValue))
            var byPlan: [PremiumPlan: Product] = [:]
            for product in found {
                if let plan = PremiumPlan(rawValue: product.id) { byPlan[plan] = product }
            }
            products = byPlan
        } catch {
            NSLog("Premium: couldn't load products: \(error.localizedDescription)")
        }
    }

    /// Asks StoreKit whether a Premium subscription is active now.
    func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  PremiumPlan(rawValue: transaction.productID) != nil,
                  transaction.revocationDate == nil else { continue }
            if let expires = transaction.expirationDate, expires < .now { continue }
            active = true
        }
        // A screenshot launch forced Premium on; leave it.
        if defaults.string(forKey: "premium") != nil { return }
        setPremium(active)
    }

    func buy(_ plan: PremiumPlan) async {
        problem = nil
        if products.isEmpty { await loadProducts() }
        guard let product = products[plan] else {
            problem = "The App Store isn't selling Premium yet. Try again later."
            return
        }
        purchasing = plan
        defer { purchasing = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    problem = "The App Store couldn't confirm that purchase."
                    return
                }
                await transaction.finish()
                await refreshEntitlement()
            case .pending:
                problem = "Your purchase is waiting for approval. Premium opens once it's approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            problem = "The purchase didn't go through. Check your connection and try again."
        }
    }

    func restore() async {
        problem = nil
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch {
            problem = "Couldn't reach the App Store to restore. Try again in a moment."
            return
        }
        await refreshEntitlement()
        if !isPremium { problem = "No Premium subscription was found for this Apple ID." }
    }

    /// The price for a plan as the App Store shows it, or the planned price before it loads.
    func price(_ plan: PremiumPlan) -> String {
        products[plan]?.displayPrice ?? plan.fallbackPrice
    }

    /// Whether the plan starts with a free trial this player can still take.
    func hasTrial(_ plan: PremiumPlan) async -> Bool {
        guard let subscription = products[plan]?.subscription, subscription.introductoryOffer != nil else {
            return plan == .yearly && products[plan] == nil
        }
        return await subscription.isEligibleForIntroOffer
    }

    private func setPremium(_ active: Bool) {
        isPremium = active
        defaults.set(active, forKey: Self.activeKey)
    }
}

/// "2 of 3 used" and when the allowance comes back, said the same way on every screen.
struct PremiumUsage: Equatable {
    let used: Int
    let of: Int
    let period: PremiumFeature.Allowance.Period
    let refreshes: Date

    /// "3 of 3 used today" or "2 of 3 used this week".
    var countLine: String {
        let when: String = period == .day ? "today" : "this week"
        return "\(used) of \(of) used \(when)"
    }

    /// "Back tomorrow" or "Back Monday", the day the allowance refreshes.
    func refreshLine(now: Date = .now, calendar: Calendar = .current) -> String {
        let today: Date = calendar.startOfDay(for: now)
        let days: Int = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: refreshes)).day ?? 1
        if days <= 1 { return "Back tomorrow" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return "Back \(formatter.string(from: refreshes))"
    }

    /// The whole line for a card: "3 of 3 used this week · Back Monday".
    func line(now: Date = .now, calendar: Calendar = .current) -> String {
        "\(countLine) · \(refreshLine(now: now, calendar: calendar))"
    }
}
