import CoreGraphics
import Foundation

/// 탭 판별기 이벤트 — View(Coordinator)가 배열 순서대로 처리한다.
enum TapClassifierEvent: Equatable {
    case pending(CGPoint)    // 첫 탭 업: 보류 시작 (임시 마커 표시)
    case confirmed(CGPoint)  // 판별 창 통과: 싱글탭 확정
    case cancelled           // 더블탭류(더블탭/원핑거 줌)로 판명: 보류 취소
}

/// "탭 즉시 확정"을 "보류 → 확정/취소"로 바꾸는 순수 상태 머신.
/// require(toFail:)는 즉시 보류 신호를 못 내고, 탭 GR+타이머는 원핑거 줌의 두 번째 터치를
/// 못 보므로 원시 터치 관찰이 필수 (스펙 '구조' 절). 시간 주입으로 유닛 테스트한다.
final class TapClassifier {
    // 판별 창 — 내장 더블탭 창보다 크거나 같게 실기기 튜닝
    var window: TimeInterval = 0.35
    // "같은 자리" 반경 — 기존 디바운스 40pt 승계
    var sameSpotRadius: CGFloat = 40

    private var pendingPoint: CGPoint?
    private var pendingTime: TimeInterval?
    // 보류를 취소시킨 두 번째 터치가 탭으로 완성되면 그 탭을 삼킨다 (더블탭의 두 번째 탭)
    private var swallowNextTap = false

    var hasPending: Bool { pendingPoint != nil }

    func tapEnded(at point: CGPoint, time: TimeInterval) -> [TapClassifierEvent] {
        if swallowNextTap {
            swallowNextTap = false
            return []
        }
        pendingPoint = point
        pendingTime = time
        return [.pending(point)]
    }

    func touchBegan(at point: CGPoint, time: TimeInterval) -> [TapClassifierEvent] {
        // 새 터치 시작은 이전 삼킴 예약을 무효화 (드래그로 끝난 원핑거 줌 뒤 정상 복귀)
        swallowNextTap = false
        guard let pending = pendingPoint, let started = pendingTime else { return [] }
        if time - started >= window {
            return finishPending(with: .confirmed(pending))
        }
        if hypot(point.x - pending.x, point.y - pending.y) <= sameSpotRadius {
            // 같은 자리 두 번째 터치 = 더블탭 or 원핑거 줌 시작 → 취소
            swallowNextTap = true
            return finishPending(with: .cancelled)
        }
        // 먼 곳 터치 → 이 보류는 더블탭이 될 수 없음 → 조기 확정
        return finishPending(with: .confirmed(pending))
    }

    func windowElapsed(time: TimeInterval) -> [TapClassifierEvent] {
        guard let pending = pendingPoint, let started = pendingTime,
              time - started >= window else { return [] }
        return finishPending(with: .confirmed(pending))
    }

    func reset() -> [TapClassifierEvent] {
        swallowNextTap = false
        guard pendingPoint != nil else { return [] }
        return finishPending(with: .cancelled)
    }

    private func finishPending(with event: TapClassifierEvent) -> [TapClassifierEvent] {
        pendingPoint = nil
        pendingTime = nil
        return [event]
    }
}
