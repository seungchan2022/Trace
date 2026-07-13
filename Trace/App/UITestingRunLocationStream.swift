import Foundation

/// UI 테스트/시뮬레이터 수동 확인용 — 0.5초마다 북쪽으로 이동하는 가짜 위치 스트림.
@MainActor
final class UITestingRunLocationStream: RunLocationStreamProtocol {
    private var feedTask: Task<Void, Never>?

    func currentAccuracy() -> RunLocationAccuracy { .full }
    func requestSessionFullAccuracy() async -> RunLocationAccuracy { .full }

    func startUpdates() -> AsyncStream<RunSample> {
        let (stream, continuation) = AsyncStream.makeStream(of: RunSample.self)
        feedTask = Task {
            var step = 0
            while Task.isCancelled == false {
                continuation.yield(RunSample(
                    timestamp: Date(),
                    latitude: 37.5666 + Double(step) * 1.5 / 111_320.0,
                    longitude: 126.9784,
                    altitudeMeters: 20,
                    speedMetersPerSecond: 3,
                    horizontalAccuracyMeters: 5,
                    verticalAccuracyMeters: 5
                ))
                step += 1
                try? await Task.sleep(for: .milliseconds(500))
            }
            continuation.finish()
        }
        return stream
    }

    func stopUpdates() {
        feedTask?.cancel()
        feedTask = nil
    }
}
