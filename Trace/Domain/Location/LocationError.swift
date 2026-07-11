import Foundation

enum LocationError: Error, Equatable, Sendable {
    case denied
    case unavailable
}
