import Foundation

/// A one-line tip, shown once, the first time a hidden gesture or a rule would help.
enum AppTip: String, CaseIterable, Identifiable {
    /// After the player's first move: what the orb is.
    case coachOrb
    /// A few moves in, with the engine's line ready: hold the board to see ahead.
    case ghostVision
    /// Right after the first Undo in a game against a rival.
    case undoHelp
    /// The first time Big Board is on during a game.
    case bigBoard
    /// On the home, once a game has been played: the gold knight in the dock has shortcuts.
    case jewelShortcuts

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .coachOrb: return "circle.circle"
        case .ghostVision: return "eye"
        case .undoHelp: return "hand.raised"
        case .bigBoard: return "hand.draw"
        case .jewelShortcuts: return "hand.tap"
        }
    }

    var text: String {
        switch self {
        case .coachOrb:
            return "Tap the orb for your coach: grades, better moves and undo."
        case .ghostVision:
            return "Hold the board to see the best line ahead. Counts as help."
        case .undoHelp:
            return "Undo counts as help: this game now earns your pieces half the XP."
        case .bigBoard:
            return "Swipe the board sideways to replay moves. Swipe up for the tools."
        case .jewelShortcuts:
            return "Hold the gold knight for shortcuts: your rivals, Online, a friend and more."
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

    /// The tip CI asks to picture with `-showcaseTip ghostVision`.
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
    ///   - lineReady: Ghost Vision has a line to show (it's on and the engine found one).
    ///   - justUndid: the player just took a move back in a game that earns XP.
    ///   - bigBoard: Big Board is on.
    static func next(playerMoves: Int, lineReady: Bool, justUndid: Bool, bigBoard: Bool,
                     _ defaults: UserDefaults = .standard) -> AppTip? {
        let wanted: [AppTip] = [
            justUndid ? .undoHelp : nil,
            bigBoard ? .bigBoard : nil,
            playerMoves >= 1 ? .coachOrb : nil,
            playerMoves >= 3 && lineReady ? .ghostVision : nil,
        ].compactMap { $0 }
        return wanted.first { canShow($0, defaults) }
    }
}
