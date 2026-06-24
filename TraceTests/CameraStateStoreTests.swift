import XCTest
@testable import Trace

final class CameraStateStoreTests: XCTestCase {
    private let suiteName = "CameraStateStoreTests"

    private func makeSUT() -> CameraStateStore {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return CameraStateStore(defaults: defaults)
    }

    func testRestoreReturnsNilWhenEmpty() {
        let sut = makeSUT()
        XCTAssertNil(sut.restore())
    }

    func testSaveAndRestoreRoundTrips() {
        let sut = makeSUT()
        sut.save(latitude: 37.5, longitude: 127.0, latitudinalMeters: 500, longitudinalMeters: 500)
        let bounds = sut.restore()
        XCTAssertEqual(bounds?.latitude, 37.5)
        XCTAssertEqual(bounds?.longitude, 127.0)
        XCTAssertEqual(bounds?.latitudinalMeters, 500)
        XCTAssertEqual(bounds?.longitudinalMeters, 500)
    }

    func testSaveOverwritesPreviousValue() {
        let sut = makeSUT()
        sut.save(latitude: 37.5, longitude: 127.0, latitudinalMeters: 500, longitudinalMeters: 500)
        sut.save(latitude: 35.0, longitude: 129.0, latitudinalMeters: 1000, longitudinalMeters: 1000)
        let bounds = sut.restore()
        XCTAssertEqual(bounds?.latitude, 35.0)
        XCTAssertEqual(bounds?.longitude, 129.0)
    }
}
