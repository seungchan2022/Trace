import Foundation
import SwiftData

// 어댑터 내부 전용 — 이 파일 밖(App/Domain/Pages)에서 import SwiftData 금지

@Model
nonisolated final class CourseRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var payload: Data

    init(id: UUID, name: String, createdAt: Date, payload: Data) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.payload = payload
    }
}
