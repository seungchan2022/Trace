import XCTest
@testable import Trace

nonisolated final class ContinuationBroadcasterTests: XCTestCase {
    @MainActor
    func testResumeAll_deliversSameResultToAllConcurrentWaiters() async throws {
        let broadcaster = ContinuationBroadcaster<Int>()

        let firstTask = Task { @MainActor in
            try await withCheckedThrowingContinuation { continuation in
                _ = broadcaster.addWaiter(continuation)
            }
        }
        let secondTask = Task { @MainActor in
            try await withCheckedThrowingContinuation { continuation in
                _ = broadcaster.addWaiter(continuation)
            }
        }

        while broadcaster.waiterCount < 2 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        broadcaster.resumeAll(with: .success(42))

        let a = try await firstTask.value
        let b = try await secondTask.value
        XCTAssertEqual(a, 42)
        XCTAssertEqual(b, 42)
        XCTAssertEqual(broadcaster.waiterCount, 0, "resumeAll 이후 다음 사이클을 위해 대기열이 비워져야 함")
    }

    @MainActor
    func testAddWaiter_exactlyOneOfConcurrentCallersIsFirst() async throws {
        let broadcaster = ContinuationBroadcaster<Int>()
        var firstIsFirst = false
        var secondIsFirst = false

        let firstTask = Task { @MainActor in
            try await withCheckedThrowingContinuation { continuation in
                firstIsFirst = broadcaster.addWaiter(continuation)
            }
        }
        let secondTask = Task { @MainActor in
            try await withCheckedThrowingContinuation { continuation in
                secondIsFirst = broadcaster.addWaiter(continuation)
            }
        }

        while broadcaster.waiterCount < 2 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        broadcaster.resumeAll(with: .success(0))
        _ = try await firstTask.value
        _ = try await secondTask.value

        XCTAssertTrue(firstIsFirst != secondIsFirst, "동시 호출자 중 정확히 하나만 최초(작업 시작)여야 함")
    }

    @MainActor
    func testAddWaiter_afterPreviousCycleResumed_treatsNextCallerAsFirstAgain() async throws {
        let broadcaster = ContinuationBroadcaster<Int>()

        let firstResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            XCTAssertTrue(broadcaster.addWaiter(continuation))
            broadcaster.resumeAll(with: .success(1))
        }
        XCTAssertEqual(firstResult, 1)

        let secondResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            XCTAssertTrue(broadcaster.addWaiter(continuation), "이전 사이클이 끝났으면 다음 waiter는 다시 최초로 취급돼야 함")
            broadcaster.resumeAll(with: .success(2))
        }
        XCTAssertEqual(secondResult, 2)
    }

    @MainActor
    func testResumeAll_deliversFailureToAllWaiters() async throws {
        struct StubError: Error, Equatable {}
        let broadcaster = ContinuationBroadcaster<Int>()

        let firstTask = Task { @MainActor in
            try await withCheckedThrowingContinuation { continuation in
                _ = broadcaster.addWaiter(continuation)
            }
        }

        while broadcaster.waiterCount < 1 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        broadcaster.resumeAll(with: .failure(StubError()))

        do {
            _ = try await firstTask.value
            XCTFail("실패 결과가 전달돼야 함")
        } catch is StubError {
            // expected
        }
    }
}
