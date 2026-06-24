import Foundation

struct CameraBounds: Equatable {
    let latitude: Double
    let longitude: Double
    let latitudinalMeters: Double
    let longitudinalMeters: Double
}

final class CameraStateStore {
    private let defaults: UserDefaults
    private enum Key {
        static let latitude = "cameraState.latitude"
        static let longitude = "cameraState.longitude"
        static let latSpan = "cameraState.latSpan"
        static let lonSpan = "cameraState.lonSpan"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(latitude: Double, longitude: Double, latitudinalMeters: Double, longitudinalMeters: Double) {
        defaults.set(latitude, forKey: Key.latitude)
        defaults.set(longitude, forKey: Key.longitude)
        defaults.set(latitudinalMeters, forKey: Key.latSpan)
        defaults.set(longitudinalMeters, forKey: Key.lonSpan)
    }

    func restore() -> CameraBounds? {
        guard defaults.object(forKey: Key.latitude) != nil else { return nil }
        return CameraBounds(
            latitude: defaults.double(forKey: Key.latitude),
            longitude: defaults.double(forKey: Key.longitude),
            latitudinalMeters: defaults.double(forKey: Key.latSpan),
            longitudinalMeters: defaults.double(forKey: Key.lonSpan)
        )
    }
}
