//
//  HapticFeedback.swift
//  Craftify
//
//  Created by Dave Van Cauwenberghe on 28/07/2026.
//

import UIKit

/// A single, prepared entry point for tactile feedback throughout Craftify.
///
/// Its app-specific name keeps call sites distinct from system haptics APIs.
@MainActor
enum HapticFeedback {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func prepareSelection() {
        selectionGenerator.prepare()
    }

    static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(type)
    }
}
