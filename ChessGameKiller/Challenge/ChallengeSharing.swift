import MessageUI
import SwiftUI
import UIKit

/// Sends an invite: a text message, an email, the share sheet, or the link copied.
/// Messages and Mail open where the phone can send them; anywhere else (the Simulator, an
/// iPad without Mail) the share sheet stands in, which, like Copy link, always works.
@MainActor
final class ChallengeSharing: NSObject, MFMessageComposeViewControllerDelegate, MFMailComposeViewControllerDelegate {
    static let shared = ChallengeSharing()

    /// Called once the sheet closes: true when the invite went (or was handed to an app to send).
    private var finished: ((Bool) -> Void)?

    static var canText: Bool { MFMessageComposeViewController.canSendText() }
    static var canMail: Bool { MFMailComposeViewController.canSendMail() }

    /// The invite as a text message.
    func text(_ invite: ChallengeInviteContent, finished: @escaping (Bool) -> Void) {
        guard Self.canText, let top = ChallengePresenter.top() else {
            return share(invite, finished: finished)
        }
        let composer = MFMessageComposeViewController()
        composer.body = invite.message
        composer.messageComposeDelegate = self
        self.finished = finished
        top.present(composer, animated: true)
    }

    /// The invite as an email.
    func mail(_ invite: ChallengeInviteContent, finished: @escaping (Bool) -> Void) {
        guard Self.canMail, let top = ChallengePresenter.top() else {
            return share(invite, finished: finished)
        }
        let composer = MFMailComposeViewController()
        composer.setSubject(invite.subject)
        composer.setMessageBody(invite.emailBody, isHTML: false)
        composer.mailComposeDelegate = self
        self.finished = finished
        top.present(composer, animated: true)
    }

    /// The share sheet: the words and the link, for any app.
    func share(_ invite: ChallengeInviteContent, finished: @escaping (Bool) -> Void) {
        guard let top = ChallengePresenter.top() else { return finished(false) }
        let sheet = UIActivityViewController(activityItems: [ChallengeShareText(invite: invite), invite.url],
                                             applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, completed, _, _ in
            finished(completed)
        }
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 120, width: 1, height: 1)
            popover.permittedArrowDirections = [.down]
        }
        top.present(sheet, animated: true)
    }

    /// The link on the clipboard.
    static func copy(_ invite: ChallengeInviteContent) {
        UIPasteboard.general.string = invite.url.absoluteString
    }

    nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                                  didFinishWith result: MessageComposeResult) {
        MainActor.assumeIsolated {
            controller.dismiss(animated: true)
            complete(result == .sent)
        }
    }

    nonisolated func mailComposeController(_ controller: MFMailComposeViewController,
                                           didFinishWith result: MFMailComposeResult, error: Error?) {
        MainActor.assumeIsolated {
            controller.dismiss(animated: true)
            complete(result == .sent || result == .saved)
        }
    }

    private func complete(_ sent: Bool) {
        let finished = finished
        self.finished = nil
        finished?(sent)
    }
}

/// Everything an invite says, worked out once.
struct ChallengeInviteContent: Equatable {
    let url: URL
    let code: String
    /// The text message, with the link.
    let message: String
    /// For the share sheet, which adds the link itself.
    let lead: String
    let subject: String
    let emailBody: String

    init(code: String, url: URL, from name: String, clock: FriendClock?, friendPlays side: FriendSeat) {
        self.url = url
        self.code = code
        message = ChallengeInviteText.message(from: name, clock: clock, friendPlays: side, url: url)
        lead = ChallengeInviteText.lead(from: name, clock: clock, friendPlays: side)
        subject = ChallengeInviteText.subject(from: name)
        emailBody = ChallengeInviteText.emailBody(from: name, clock: clock, friendPlays: side, url: url, code: code)
    }

    /// The invite to a player's own game, from its record.
    init(game: FriendGame, name: String) {
        self.init(code: game.code, url: ChallengeLink.inviteURL(for: game.code), from: name, clock: game.clock,
                  friendPlays: game.seat.opposite)
    }
}

/// The words for the share sheet: Mail takes the subject from here, everything else the text.
final class ChallengeShareText: NSObject, UIActivityItemSource {
    private let invite: ChallengeInviteContent

    init(invite: ChallengeInviteContent) {
        self.invite = invite
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        invite.lead
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        invite.lead
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        invite.subject
    }
}

/// Finds where to present from, and whether anything is still on its way in or out.
@MainActor
enum ChallengePresenter {
    /// The view controller on top of everything, to present the share sheet and Messages from.
    static func top() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    /// A sheet or cover is opening or closing somewhere on screen.
    static var isTransitioning: Bool {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in windows {
            var controller = window.rootViewController
            while let current = controller {
                if current.isBeingPresented || current.isBeingDismissed || current.transitionCoordinator != nil {
                    return true
                }
                controller = current.presentedViewController
            }
        }
        return false
    }
}
