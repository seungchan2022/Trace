import Foundation
import SwiftData

// 어댑터 내부 전용 — 이 파일 밖(App/Domain/Pages)에서 import SwiftData 금지

@Model
final class RunRecordModel {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    // 거리·시간·고도 상승은 목록 성능용 캐시 컬럼 — 진실의 원천은 payload의 원시 샘플(스펙 §2)
    var distanceMeters: Double
    var durationSeconds: Double
    var elevationGainMeters: Double
    var payload: Data

    init(
        id: UUID, startedAt: Date, distanceMeters: Double,
        durationSeconds: Double, elevationGainMeters: Double, payload: Data
    ) {
        self.id = id
        self.startedAt = startedAt
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.elevationGainMeters = elevationGainMeters
        self.payload = payload
    }
}
