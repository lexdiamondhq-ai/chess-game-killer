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
    private var premium: Premium { .shared }

    private var theme: BoardTheme { .named(themeID) }
    private var accent: Color { theme.accent ?? PremiumStyle.gold }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ThemeBackdrop(theme: theme).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    PremiumOfferHeader(accent: accent)
                    if let feature {
                        PremiumReasonCard(text: feature.limitLine, accent: accent)
                    }
                    PremiumBenefitList(accent: accent)
                    plans
                    buyButton
                    PremiumFinePrint(plan: plan, price: premium.price(plan), trial: plan == .yearly && trial)
                    footerLinks
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            closeButton
        }
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .tint(accent)
        .task {
            premium.start()
            if premium.products.isEmpty { await premium.loadProducts() }
            trial = await premium.hasTrial(.yearly)
        }
        .onChange(of: premium.isPremium) { _, now in
            if now { dismiss() }
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .glassPane(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .padding(.trailing, 14)
        .padding(.top, 8)
        .accessibilityLabel("Close")
    }

    private var plans: some View {
        VStack(spacing: 10) {
            PremiumPlanCard(plan: .yearly, price: premium.price(.yearly), selected: plan == .yearly,
                            note: "Just $5 a month. Save 50%", accent: accent) { plan = .yearly }
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
                    if busy { ProgressView().tint(.black) }
                }
                .font(.system(.headline, design: .themed))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(busy)
            if let problem = premium.problem {
                Text(problem)
                    .font(.system(.footnote, design: .themed))
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
        }
        .font(.system(.footnote, design: .themed).weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

enum PremiumStyle {
    static let gold = Color(hex: 0xD9A65E)
    /// Apple's standard licence agreement, which the App Store applies to subscriptions.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

private struct PremiumOfferHeader: View {
    let accent: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 68, height: 68)
                .glassPane(Circle(), tint: accent)
            Text("Premium")
                .font(.system(size: 34, weight: .bold, design: .themed))
            Text("Get better faster. Your coach learns how you play and builds every session around it.")
                .font(.system(.body, design: .themed))
                .foregroundStyle(.secondary)
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
                .font(.system(.subheadline, design: .themed).weight(.medium))
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
        Benefit(symbol: "person.text.rectangle", title: "A coach that learns you",
                detail: "Your style, strengths and leaks from every game, and a plan rebuilt after each one."),
        Benefit(symbol: "backward.circle", title: "Full Rewind on every game",
                detail: "Ghost lines, second chances and what could have been."),
        Benefit(symbol: "puzzlepiece.extension", title: "Unlimited puzzles",
                detail: "115,000 rated puzzles, Puzzle Rush, Cycles and your review queue."),
        Benefit(symbol: "graduationcap", title: "Every lesson and drill",
                detail: "All 15 lessons, 3,865 openings, 22 endgames, master games and Blindfold."),
        Benefit(symbol: "eye", title: "Ghost Vision any time",
                detail: "Plus Talk It Through 10 times a day and 3 photo scans a day."),
        Benefit(symbol: "square.grid.3x3", title: "Every board look",
                detail: "Every set and every rival's board."),
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.title)
                    .font(.system(.headline, design: .themed))
                Text(benefit.detail)
                    .font(.system(.subheadline, design: .themed))
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
                        .font(.system(.headline, design: .themed))
                    if let note {
                        Text(note)
                            .font(.system(.subheadline, design: .themed).weight(.semibold))
                            .foregroundStyle(accent)
                    }
                }
                Spacer(minLength: 8)
                Text("\(price) \(plan.per)")
                    .font(.system(.subheadline, design: .themed).weight(.semibold).monospacedDigit())
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
            .font(.system(.footnote, design: .themed))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var words: String {
        let renewal = "Renews at \(price) \(plan.per) until you cancel. Cancel any time in your Apple ID's subscription settings."
        return trial ? "7 days free, then \(price) \(plan.per). " + renewal : renewal
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
    @State private var offer: PremiumFeature?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "crown.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accent)
            Text(feature.limitLine)
                .font(.system(.subheadline, design: .themed).weight(.medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                offer = feature
            } label: {
                Text("See Premium")
                    .font(.system(.headline, design: .themed))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: 260)
                    .frame(height: 48)
                    .background(accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
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
            .font(.system(.caption, design: .themed).weight(.bold))
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

    var body: some View {
        let accent: Color = theme.accent ?? PremiumStyle.gold
        let active: Bool = premium.isPremium
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(active ? "Premium is on" : "Premium")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text(active ? "Thank you. Everything is open." : "A coach that learns you, full Rewind, unlimited puzzles and every look.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassPane(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(active)
    }
}
