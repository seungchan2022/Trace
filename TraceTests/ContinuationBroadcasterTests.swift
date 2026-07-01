import XCTest
@testable import Trace

@MainActor
final class ContinuationBroadcasterTests: XCTestCase {
    func testResumeAll_deliversSameResultToAllConcurrentWaiters() async throws {
        let broadcaster = ContinuationBroadcaster<Int>()

        async let first: Int = withCheckedThrowingContinuation { @MainActor continuation in
            _ = broadcaster.addWaiter(continuation)
        }
        async let second: Int = withCheckedThrowingContinuation { @MainActor continuation in
            _ = broadcaster.addWaiter(continuation)
        }

        while broadcaster.waiterCount < 2 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        broadcaster.resumeAll(with: .success(42))

        let (a, b) = try await (first, second)
        XCTAssertEqual(a, 42)
        XCTAssertEqual(b, 42)
        XCTAssertEqual(broadcaster.waiterCount, 0, "resumeAll 이후 다음 사이클을 위해 대기열이 비워져야 함")
    }

    func testAddWaiter_exactlyOneOfConcurrentCallersIsFirst() async throws {
        let broadcaster = ContinuationBroadcaster<Int>()
        var firstIsFirst = false
        var secondIsFirst = false

        async let first: Int = withCheckedThrowingContinuation { @MainActor continuation in
            firstIsFirst = broadcaster.addWaiter(continuation)
        }
        async let second: Int = withCheckedThrowingContinuation { @MainActor continuation in
            secondIsFirst = broadcaster.addWaiter(continuation)
        }

        while broadcaster.waiterCount < 2 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        broadcaster.resumeAll(with: .success(0))
        _ = try await (first, second)

        XCTAssertTrue(firstIsFirst != secondIsFirst, "동시 호출자 중 정확히 하나만 최초(작업 시작)여야 함")
    }

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

    func testResumeAll_deliversFailureToAllWaiters() async throws {
        struct StubError: Error, Equatable {}
        let broadcaster = ContinuationBroadcaster<Int>()

        async let first: Int = withCheckedThrowingContinuation { @MainActor continuation in
            _ = broadcaster.addWaiter(continuation)
        }

        while broadcaster.waiterCount < 1 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        broadcaster.resumeAll(with: .failure(StubError()))

        do {
            _ = try await first
            XCTFail("실패 결과가 전달돼야 함")
        } catch is StubError {
            // expected
        }
    }
}
