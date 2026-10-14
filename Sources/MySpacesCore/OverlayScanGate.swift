import Foundation

public struct ScanTicket: Equatable, Sendable {
    let session: Int
    let sequence: Int
}

/// Decides what to do with each Mission Control caption scan. Enforces the spec's safety
/// rule (a caption/desktop mismatch draws nothing for the rest of that Mission Control
/// session) and makes sure an older scan finishing late never overwrites a newer one.
public final class OverlayScanGate {
    public enum Decision: Equatable {
        case show([LabelPlacement])
        case hide
        case ignore
    }

    private var session = 0
    private var isOpen = false
    private var disabled = false
    private var issued = 0
    private var lastDecided = 0

    public init() {}

    public func open() {
        session += 1
        isOpen = true
        disabled = false
        issued = 0
        lastDecided = 0
    }

    public func close() {
        session += 1
        isOpen = false
    }

    /// A ticket for a new scan, or nil when scanning is pointless (closed or disabled).
    public func issueScan() -> ScanTicket? {
        guard isOpen, !disabled else { return nil }
        issued += 1
        return ScanTicket(session: session, sequence: issued)
    }

    /// `placements` is LabelMapper's result: nil means the captions did not match the desktops.
    public func decide(_ ticket: ScanTicket, placements: [LabelPlacement]?) -> Decision {
        guard isOpen, ticket.session == session, ticket.sequence > lastDecided else { return .ignore }
        lastDecided = ticket.sequence
        guard !disabled, let placements else {
            disabled = true
            return .hide
        }
        return .show(placements)
    }
}
