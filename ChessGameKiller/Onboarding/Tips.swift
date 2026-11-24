import Foundation

/// A one-line tip, shown once, the first time a hidden gesture or a rule would help.
enum AppTip: String, CaseIterable, Identifiable {
    /// After the player's first move: what the orb is.
    case coachOrb
    /// Right after the first Undo in a game against a rival.
    case undoHelp
    /// On the home, once a game has been played: the gold knight in the dock has shortcuts.
    case jewelShortcuts
    /// A few moves into a game against the Ashen King: sideways, the phone shows his hall.
    case kingsHall
    /// The same a few moves into a game against the Cub, whose forest opens sideways too
    /// (Alex's pick 9A, screen review 2026-11-19).
    case cubForest

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .coachOrb: return "circle.circle"
        case .undoHelp: return "hand.raised"
        case .jewelShortcuts: return "hand.tap"
        case .kingsHall, .cubForest: return "rectangle.landscape.rotate"
        }
    }

    var text: String {
        switch self {
        case .coachOrb:
            return "Tap the orb for your coach: grades, better moves and undo."
        case .undoHelp:
            return "Undo counts as help: this game now earns your pieces half the XP."
        case .jewelShortcuts:
            return "Tap Analyze to scan a board. Tap the gold knight for Quick play and more."
        case .kingsHall:
            return "Turn your phone sideways to face the King across his table."
        case .cubForest:
            return "Turn your phone sideways to face the Cub in his forest."
        }
    }

    /// Where a tip is told once it's been shown.
    var key: String { "tip.seen.\(rawValue)" }
}

/// Which tips have been shown. Each is shown once; Settings can bring them all back.
enum TipBook {
    /// CI's pictures (`-showcase …`, `-tipsOff YES`) show no tips unless one is asked for.
    static func suppressed(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: "tipsOff") || defaults.string(forKey: "showcase") != nil
    }

    /// The tip CI asks to picture with `-showcaseTip coachOrb`.
    static func showcased(_ defaults: UserDefaults = .standard) -> AppTip? {
        defaults.string(forKey: "showcaseTip").flatMap(AppTip.init(rawValue:))
    }

    static func hasSeen(_ tip: AppTip, _ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: tip.key)
    }

    /// Whether this tip may show now: not seen yet, and tips aren't off.
    static func canShow(_ tip: AppTip, _ defaults: UserDefaults = .standard) -> Bool {
        !suppressed(defaults) && !hasSeen(tip, defaults)
    }

    static func markSeen(_ tip: AppTip, _ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: tip.key)
    }

    static func resetAll(_ defaults: UserDefaults = .standard) {
        for tip in AppTip.allCases { defaults.removeObject(forKey: tip.key) }
    }

    /// The tip a moment in a game calls for, if any, in order of how much it helps.
    /// - Parameters:
    ///   - playerMoves: moves the player has made this game.
    ///   - justUndid: the player just took a move back in a game that earns XP.
    ///   - facingKing: the game is against the Ashen King, whose hall opens with the phone on its side.
    ///   - facingCub: the game is against the Cub, whose forest opens the same way.
    static func next(playerMoves: Int, justUndid: Bool, facingKing: Bool = false, facingCub: Bool = false,
                     _ defaults: UserDefaults = .standard) -> AppTip? {
        let wanted: [AppTip] = [
            justUndid ? .undoHelp : nil,
            playerMoves >= 1 ? .coachOrb : nil,
            facingKing && playerMoves >= 2 ? .kingsHall : nil,
            facingCub && playerMoves >= 2 ? .cubForest : nil,
        ].compactMap { $0 }
        return wanted.first { canShow($0, defaults) }
    }
}
