import StoreKit
import SwiftUI

/// The one Premium screen: what it adds, the two plans with the yearly one picked, and a clear
/// way out. Opened when a free allowance runs out (it says which) or from Settings.
struct PremiumOfferView: View {
    /// What the player just reached the end of, if anything.
    let feature: PremiumFeature?

    @AppStorage("boardTheme") private var themeID: BoardTheme.ID = .gilded
    @Environment(\.dismiss) private var dismiss
    @State private var plan: PremiumPlan = .yearly
    @State private var trial = true
    /// Apple's page for the plan, for a subscriber who came here from You.
    @State private var managing = false
    @AppStorage("haptics") private var hapticsOn = true
    /// Premium was bought on this sheet a moment ago: it says so before it closes.
    @State private var justBought = false
    /// Bumps to bounce the crown.
    @State private var crown = 0
    private var premium: Premium { .shared }

    private var theme: BoardTheme { .named(themeID) }
    /// The page's gold ink on the home's pages, or the board's own gold.
    private var accent: Color {
        theme.screenTone != nil ? theme.trainingAccent : (theme.accent ?? PremiumStyle.gold)
    }
    private var onAccent: Color { theme.screenIsDark ? .black : .white }
    /// On the home's pages the sheet is dressed as Home is: a gold medallion and the gold button.
    private var gilded: Bool { theme.screenTone != nil }
    private var mainInk: Color { gilded ? Polish.onMetal : onAccent }

    /// Behind the sheet's one main button: the app's gold, or the board's accent on the older home.
    @ViewBuilder
    private var mainFill: some View {
        if gilded {
            PolishedFill(shape: Capsule())
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(accent)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TrainingBackdrop(theme: theme).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    PremiumOfferHeader(accent: accent, gilded: gilded, bounce: crown)
                    if justBought {
                        PremiumOwnedCard(text: nil, accent: accent)
                            .transition(.scale(scale: 0.94).combined(with: .opacity))
                    } else if premium.isPremium {
                        // Already subscribed: only Premium's own daily caps lead here. Say so,
                        // and never ask them to buy it again.
                        PremiumOwnedCard(text: feature.map(premium.limitLine), accent: accent)
                        doneButton
                        // The same Apple page as Settings' Premium card (Alex's pick 14A, 2026-11-19).
                        Button("Manage plan") { managing = true }
                            .font(.app(.subheadline, weight: .semibold))
                            .foregroundStyle(accent)
                            .manageSubscriptionsSheet(isPresented: $managing)
                    } else {
                        if let feature {
                            PremiumReasonCard(text: feature.limitLine, accent: accent)
                        }
                        PremiumBenefitList(accent: accent)
                        plans
                        buyButton
                        PremiumFinePrint(plan: plan, price: premium.price(plan), trial: plan == .yearly && trial)
                        footerLinks
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 64)
                .padding(.bottom, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            closeButton
        }
        .screenScheme(theme)
        .tint(accent)
        .task {
            // A problem from the last visit (a purchase that didn't go through) isn't news now.
            premium.problem = nil
            premium.start()
            if premium.products.isEmpty { await premium.loadProducts() }
            trial = await premium.hasTrial(.yearly)
        }
        .onChange(of: premium.isPremium) { _, now in
            guard now else { return }
            // Bought here: the crown bounces and the sheet says "You have Premium" for a
            // moment, with a buzz and the chime, before it closes by itself.
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { justBought = true }
            crown += 1
            SoundPlayer.shared.play(.win)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.4))
                dismiss()
            }
        }
        .sensoryFeedback(.success, trigger: premium.isPremium) { _, now in now && hapticsOn }
    }

    /// A 44-point target with the visible circle inside it, set in from the sheet's rounded
    /// corner so a thumb reaching for the corner still lands on it.
    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 38)
                .glassPane(Circle())
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 12)
        .padding(.top, 10)
        .accessibilityLabel("Close")
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(.app(.headline))
                .foregroundStyle(mainInk)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background { mainFill }
                // The metal takes no touches, so the whole button is named as the target.
                .contentShape(Rectangle())
        }
        .buttonStyle(ChallengePressStyle())
    }

    private var plans: some View {
        VStack(spacing: 10) {
            PremiumPlanCard(plan: .yearly, price: premium.price(.yearly), selected: plan == .yearly,
                            note: premium.yearlyNote, accent: accent) { plan = .yearly }
            PremiumPlanCard(plan: .monthly, price: premium.price(.monthly), selected: plan == .monthly,
                            note: nil, accent: accent) { plan = .monthly }
        }
    }

    private var buyButton: some View {
        let busy: Bool = premium.purchasing != nil
        let title: String = plan == .yearly && trial ? "Start 7-day free trial" : "Subscribe"
        return VStack(spacing: 10) {
            Button {
                Task { await premium.buy(plan) }
            } label: {
                ZStack {
                    Text(title).opacity(busy ? 0 : 1)
                    if busy { ProgressView().tint(mainInk) }
                }
                .font(.app(.headline))
                .foregroundStyle(mainInk)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background { mainFill }
                // The metal takes no touches, so the whole button is named as the target.
                .contentShape(Rectangle())
            }
            .buttonStyle(ChallengePressStyle())
            .disabled(busy)
            if let problem = premium.problem {
                Text(problem)
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var footerLinks: some View {
        HStack(spacing: 18) {
            Button(premium.isRestoring ? "Restoring…" : "Restore purchases") {
                Task { await premium.restore() }
            }
            .disabled(premium.isRestoring)
            Link("Terms of use", destination: PremiumStyle.terms)
            Link("Privacy", destination: PremiumStyle.privacy)
        }
        .font(.app(.footnote, weight: .semibold))
        .foregroundStyle(.secondary)
    }
}

enum PremiumStyle {
    static let gold = Color(hex: 0xD9A65E)
    /// Apple's standard licence agreement, which the App Store applies to subscriptions.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// What leaves the phone and why (play/public/privacy), required beside a subscription offer.
    static let privacy = URL(string: "https://play.chess-game-killer.workers.dev/privacy/")!
}

private struct PremiumOfferHeader: View {
    let accent: Color
    /// The crown on a solid gold medallion, as on Home's pages.
    var gilded = false
    /// Bumps to bounce the crown, as Premium is bought.
    var bounce = 0

    var body: some View {
        VStack(spacing: 12) {
            if gilded {
                Image(systemName: "crown.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Polish.onMetal)
                    .symbolEffect(.bounce, value: bounce)
                    .frame(width: 76, height: 76)
                    .background { PolishedFill(shape: Circle()) }
                    .padding(.bottom, 2)
            } else {
                Image(systemName: "crown.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(accent)
                    .symbolEffect(.bounce, value: bounce)
                    .frame(width: 68, height: 68)
                    .glassPane(Circle(), tint: accent)
            }
            Text("Premium")
                .font(.display(size: 38, weight: .medium))
            Text("Get better faster. Your coach learns how you play and builds every session around it.")
                .font(.app(.body))
                .foregroundStyle(Color.quietInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PremiumReasonCard: View {
    let text: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.top, 2)
            Text(text)
                .font(.app(.subheadline, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassPane(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// What Premium adds, one line each.
private struct PremiumBenefitList: View {
    let accent: Color

    struct Benefit: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    static let benefits: [Benefit] = [
        Benefit(symbol: "person.text.rectangle.fill", title: "A coach that learns you",
                detail: "Your style, strengths and leaks from every game, and a plan rebuilt after each one."),
        Benefit(symbol: "backward.circle.fill", title: "Full Rewind on every game",
                detail: "Your coach talks you through the whole game. Ghost lines and second chances."),
        Benefit(symbol: "puzzlepiece.extension.fill", title: "Unlimited puzzles",
                detail: "115,000 rated puzzles, Puzzle Rush, Cycles and your review queue."),
        Benefit(symbol: "graduationcap.fill", title: "Every lesson and drill",
                detail: "All 15 lessons, 3,865 openings, 22 endgames, master games and unlimited See ahead."),
        Benefit(symbol: "bubble.left.and.bubble.right.fill", title: "Talk It Through every day",
                detail: "Up to 50 talks and 30 photo scans a day."),
        // Premium opens every rival (RivalLadder.opensEverything); the page now says so
        // (Alex, 2026-11-11, audit pick R4).
        Benefit(symbol: "shield.fill", title: "Every rival, from day one",
                detail: "Face any of the five without beating the ones before."),
        // Every set of pieces is free for everyone; the boards are what Premium opens
        // (four free, ten in all), so the line promises only that (inspection, 2026-11-14).
        Benefit(symbol: "square.grid.3x3.fill", title: "Every board look",
                detail: "All \(BoardTheme.all.count - BoardTheme.rivals.count) boards to play on."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Self.benefits) { benefit in
                PremiumBenefitRow(benefit: benefit, accent: accent)
            }
        }
        .padding(18)
        .glassPane(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct PremiumBenefitRow: View {
    let benefit: PremiumBenefitList.Benefit
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: benefit.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [accent.opacity(0.26), accent.opacity(0.1)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(accent.opacity(0.4), lineWidth: 0.75)
                        }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.title)
                    .font(.display(.headline, weight: .semibold))
                Text(benefit.detail)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PremiumPlanCard: View {
    let plan: PremiumPlan
    let price: String
    let selected: Bool
    let note: String?
    let accent: Color
    let pick: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: pick) {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? accent : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name)
                        .font(.app(.headline))
                    if let note {
                        Text(note)
                            .font(.app(.subheadline, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                }
                Spacer(minLength: 8)
                Text("\(price) \(plan.per)")
                    .font(.app(.subheadline, weight: .semibold).monospacedDigit())
            }
            .padding(16)
            .glassPane(shape)
            .overlay {
                shape.strokeBorder(selected ? accent : Color.clear, lineWidth: 1.5)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(plan.name), \(price) \(plan.per)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PremiumFinePrint: View {
    let plan: PremiumPlan
    let price: String
    let trial: Bool

    var body: some View {
        Text(words)
            .font(.app(.footnote))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var words: String {
        let renewal = "Renews at \(price) \(plan.per) until you cancel. Cancel any time in your Apple ID's subscription settings."
        return trial ? "7 days free, then \(price) \(plan.per). " + renewal : renewal
    }
}

/// For a player who already has Premium: thanks, and where today's cap stops if one did.
private struct PremiumOwnedCard: View {
    let text: String?
    let accent: Color

    var body: some View {
        VStack(spacing: 10) {
            Label("You have Premium", systemImage: "checkmark.seal.fill")
                .font(.app(.headline))
                .foregroundStyle(accent)
            Text(text ?? "Thank you. Everything is open.")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassPane(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

extension Premium {
    /// Under Premium in Home's You panel: what it is, or that it is on.
    var youLine: String {
        isPremium ? "It's on. Everything is open" : "Everything, with no limits"
    }
}

// MARK: - Showing the offer

extension View {
    /// Shows the Premium offer while `feature` is set.
    func premiumOffer(_ feature: Binding<PremiumFeature?>) -> some View {
        sheet(item: feature) { feature in
            PremiumOfferView(feature: feature)
        }
    }
}

/// Where a free allowance ends inside a screen: the reason, and a way to Premium.
struct PremiumLimitCard: View {
    let feature: PremiumFeature
    let accent: Color
    /// On the gold looks the crown sits on its amber stone and the button is the gold main
    /// button; a look with its own color (Neon, Blueprint) keeps that color.
    var gilded = false
    @State private var offer: PremiumFeature?

    var body: some View {
        VStack(spacing: 14) {
            if gilded {
                JewelIcon(symbol: "crown.fill", stone: .amber, size: 40)
            } else {
                Image(systemName: "crown.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text(Premium.shared.limitLine(feature))
                .font(.app(.subheadline, weight: .medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // Premium players already have it: their cap comes back tomorrow, nothing to buy.
            if !Premium.shared.isPremium {
                Button {
                    offer = feature
                } label: {
                    Text("See Premium")
                        .font(.app(.headline))
                        .foregroundStyle(gilded ? Polish.onMetal : Color.black)
                        .frame(maxWidth: 260)
                        .frame(height: 48)
                        .background {
                            if gilded {
                                PolishedFill(shape: Capsule(), quiet: true)
                            } else {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent)
                            }
                        }
                        // The metal takes no touches, so the whole button is named as the target.
                        .contentShape(Rectangle())
                }
                .buttonStyle(ChallengePressStyle())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassPane(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .premiumOffer($offer)
    }
}

/// The small crown on a row only Premium opens.
struct PremiumTag: View {
    let accent: Color

    var body: some View {
        Label("Premium", systemImage: "crown.fill")
            .font(.app(.caption, weight: .bold))
            .foregroundStyle(accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accent.opacity(0.14), in: Capsule())
            .fixedSize()
    }
}

/// Settings' Premium row: what it is, or that it's on.
struct PremiumSettingsCard: View {
    let theme: BoardTheme
    let open: () -> Void
    private var premium: Premium { .shared }
    /// Apple's own page for the subscription, for a player who has Premium.
    @State private var managing = false

    var body: some View {
        let active: Bool = premium.isPremium
        Button {
            // With Premium on there is nothing to sell: the row opens Apple's page to change or
            // cancel the plan (inspection, 2026-11-14: there was no way to it from the app).
            if active { managing = true } else { open() }
        } label: {
            HStack(spacing: 8) {
                JewelIcon(symbol: "crown.fill", stone: .amber, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(active ? "Premium is on" : "Premium")
                        .font(.display(.body, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text(active ? "Everything is open. Tap to manage your plan." : "A coach that learns you, full Rewind, unlimited puzzles and every look.")
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassPane(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .manageSubscriptionsSheet(isPresented: $managing)
    }
}
