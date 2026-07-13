import XCTest
@testable import Trace

final class RunSampleDumpEncoderTests: XCTestCase {
    func test_덤프JSON에_샘플원시값과_필터판정이_들어간다() throws {
        let entry = RunSampleDumpEntry(
            sample: RunSample(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                latitude: 37.5, longitude: 127.0,
                altitudeMeters: 12, speedMetersPerSecond: 3,
                horizontalAccuracyMeters: 40, verticalAccuracyMeters: 5
            ),
            accepted: false
        )
        let data = try RunSampleDumpEncoder.jsonData(
            entries: [entry], startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"accepted\" : false"))
        XCTAssertTrue(json.contains("\"horizontalAccuracyMeters\" : 40"))
        XCTAssertTrue(json.contains("2023-11-14")) // ISO8601 날짜
    }
}
