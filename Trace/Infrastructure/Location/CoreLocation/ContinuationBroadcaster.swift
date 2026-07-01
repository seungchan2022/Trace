import Foundation

// 진행 중인 비동기 요청 하나의 결과를, 그 사이 함께 대기하게 된 모든 호출자에게 동일하게 전달한다.
// CoreLocationService.currentLocation()이 여러 곳(부트스트랩·재중심 버튼)에서 겹쳐 호출될 때
// 뒤에 온 호출이 즉시 실패하지 않고 먼저 시작된 요청의 결과를 함께 기다리도록 하기 위함.
@MainActor
final class ContinuationBroadcaster<Value> {
    private var pending: [CheckedContinuation<Value, Error>] = []

    var waiterCount: Int { pending.count }

    // 이 호출로 대기열이 비어 있다가 처음 채워졌으면 true(호출자가 실제 작업을 시작해야 함).
    func addWaiter(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        pending.append(continuation)
        return pending.count == 1
    }

    func resumeAll(with result: Result<Value, Error>) {
        let waiters = pending
        pending = []
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }
}
