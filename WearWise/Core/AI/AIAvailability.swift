import Foundation
import FoundationModels

/// App-level view of whether on-device AI can be used right now.
enum AIAvailability: Equatable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknownUnavailable

    var isAvailable: Bool { self == .available }

    var message: String {
        switch self {
        case .available:
            "On-device AI is ready. Photos never leave your iPhone."
        case .deviceNotEligible:
            "This device doesn't support Apple Intelligence. You can still describe items yourself."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in Settings to get AI suggestions. Manual entry still works."
        case .modelNotReady:
            "The on-device model is still downloading or preparing. Try again shortly."
        case .unknownUnavailable:
            "On-device AI isn't available right now. Manual entry still works."
        }
    }
}

enum AIAvailabilityChecker {
    static func current(model: SystemLanguageModel = .default) -> AIAvailability {
        switch model.availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady): .modelNotReady
        case .unavailable: .unknownUnavailable
        }
    }
}
