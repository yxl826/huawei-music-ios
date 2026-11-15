import Foundation

struct AppSettings: Codable, Equatable {
    var quality: Quality
    var syncHistory: Bool
    var playMode: PlayMode

    static let fallback = AppSettings(quality: .standard, syncHistory: true, playMode: .sequential)
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persist() }
    }

    private let storageKey = "app-settings-v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = .fallback
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
