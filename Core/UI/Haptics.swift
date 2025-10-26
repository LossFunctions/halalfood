import UIKit

enum Haptics {
    static func favoriteToggled(isNowFavorite: Bool) {
        if isNowFavorite {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } else {
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.impactOccurred()
        }
    }
}

