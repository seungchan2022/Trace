import MapKit
import SwiftUI

// mapPins만 별도 파일로 분리 — CoursePlannerPage 본체가 SwiftLint type_body_length(300줄) 기준을
// 넘지 않도록 나머지 컴포넌트 확장 파일들(BottomSheet/Controls/CourseList)과 같은 패턴으로 뺀다.
extension CoursePlannerPage {
    var mapPins: [MapPin] {
        let accentUIColor = UIColor(named: "AccentColor") ?? .systemGreen
        let dangerUIColor = UIColor(named: "Danger") ?? .systemRed
        var pins: [MapPin] = []
        if let course = viewModel.course {
            if viewModel.isClosedCourse, let first = course.coordinates.first {
                // 닫힌 코스: 출발·도착이 같은 지점 — 병합 핀 하나만
                pins.append(MapPin(
                    coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                    title: "출발/도착",
                    color: accentUIColor,
                    systemImage: "figure.run",
                    role: .merged
                ))
            } else {
                if let first = course.coordinates.first {
                    pins.append(MapPin(
                        coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                        title: "출발",
                        color: accentUIColor,
                        systemImage: "figure.run",
                        role: .start
                    ))
                }
                if let last = course.coordinates.last, course.coordinates.count > 1 {
                    pins.append(MapPin(
                        coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
                        title: "도착",
                        color: dangerUIColor,
                        systemImage: "flag.checkered",
                        role: .end
                    ))
                }
            }
        }
        // tap 모드에서 pendingTapStart는 코스가 비어 있을 때만 설정됨 (최초 2탭 대기)
        if viewModel.interactionMode == .tap, let start = viewModel.pendingTapStart {
            pins.append(MapPin(
                coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude),
                title: "출발",
                color: accentUIColor,
                systemImage: "figure.run",
                role: .pendingStart
            ))
        }
        // 판별 창(~0.35초) 보류 중 임시 마커 — 확정된 출발/도착 핀(초록 러너/빨강 깃발)과
        // 혼동되지 않도록 중립 스타일을 쓴다. 예전엔 첫 탭/두번째 탭 여부로 출발·도착 스타일을
        // 그대로 재사용했는데, 그 판정(pendingTapStart == nil)이 라우팅 완료 전에 이미 바뀌어버려
        // 확정 직후 짧게 라벨이 뒤바뀌어 보이는 버그가 있었다 (2026-07-05 실기기 확인).
        // 중립 스타일은 위치 구분이 필요 없어 그 버그 자체가 성립하지 않는다.
        if viewModel.interactionMode == .tap, let pending = viewModel.pendingTapMarker {
            pins.append(MapPin(
                coordinate: CLLocationCoordinate2D(latitude: pending.latitude, longitude: pending.longitude),
                title: "확인 중",
                color: .systemGray,
                systemImage: "circle.dashed",
                role: .pendingStart
            ))
        }
        return pins
    }
}
