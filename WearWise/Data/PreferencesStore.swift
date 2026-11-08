import Foundation
import Observation

/// Persists style preferences in UserDefaults. Small, single-value settings don't need SwiftData.
@MainActor
@Observable
final class PreferencesStore {
    private(set) var preferences: StylePreferences

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    init(defaults: UserDefaults = .standard, key: String = "stylePreferences") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(StylePreferences.self, from: data) {
            preferences = saved
        } else {
            preferences = .none
        }
    }

    func toggleFavorite(_ color: ClothingColor) {
        preferences.toggleFavorite(color)
        save()
    }

    func toggleAvoided(_ color: ClothingColor) {
        preferences.toggleAvoided(color)
        save()
    }

    func setUsualFormality(_ formality: Formality?) {
        preferences.usualFormality = formality
        save()
    }

    func reset() {
        preferences = .none
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: key)
        }
    }
}
