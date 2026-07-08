import Foundation

// 직렬화 포맷은 어댑터 내부 DTO — 도메인 타입에 Codable을 직접 붙이면 도메인 리팩터링이
// 기존 blob을 해독 불가로 만든다. blob에는 포맷 버전을 둔다 (MVP11 스펙 §2).
enum CoursePersistenceDTO {
    static let currentVersion = 1

    struct Coordinate: Codable {
        let lat: Double
        let lon: Double
    }

    struct Segment: Codable {
        enum Kind: String, Codable {
            case tapped, drawn, roundTrip
        }
        let kind: Kind
        let coordinates: [Coordinate]
        let distanceMeters: Double
    }

    struct DraftEntry: Codable {
        let id: UUID
        let order: Int
        let placedAtFront: Bool
        let anchorID: UUID?
        let anchorInsertsBefore: Bool
        let segment: Segment

        init(
            id: UUID, order: Int, placedAtFront: Bool,
            anchorID: UUID?, anchorInsertsBefore: Bool, segment: Segment
        ) {
            self.id = id
            self.order = order
            self.placedAtFront = placedAtFront
            self.anchorID = anchorID
            self.anchorInsertsBefore = anchorInsertsBefore
            self.segment = segment
        }

        // 구버전 blob(anchorInsertsBefore 필드 없음) 하위호환: 옛 왕복 엔트리는 항상 anchor
        // 뒤에 삽입됐으므로 false가 정확한 기본값이다 — 필드 누락을 손상으로 취급하지 않는다.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            order = try container.decode(Int.self, forKey: .order)
            placedAtFront = try container.decode(Bool.self, forKey: .placedAtFront)
            anchorID = try container.decodeIfPresent(UUID.self, forKey: .anchorID)
            anchorInsertsBefore = try container.decodeIfPresent(Bool.self, forKey: .anchorInsertsBefore) ?? false
            segment = try container.decode(Segment.self, forKey: .segment)
        }
    }

    struct Draft: Codable {
        let version: Int
        let entries: [DraftEntry]
        let nextOrder: Int
    }

    struct Course: Codable {
        let version: Int
        let segments: [Segment]
    }
}

// MARK: - 도메인 ↔ DTO 매핑

extension CoursePersistenceDTO.Coordinate {
    init(_ c: CourseCoordinate) {
        self.init(lat: c.latitude, lon: c.longitude)
    }
    var domain: CourseCoordinate {
        CourseCoordinate(latitude: lat, longitude: lon)
    }
}

extension CoursePersistenceDTO.Segment {
    init(_ segment: CourseSegment) {
        let coords = segment.coordinates.map(CoursePersistenceDTO.Coordinate.init)
        switch segment {
        case .tapped(_, let d):    self.init(kind: .tapped, coordinates: coords, distanceMeters: d)
        case .drawn(_, let d):     self.init(kind: .drawn, coordinates: coords, distanceMeters: d)
        case .roundTrip(_, let d): self.init(kind: .roundTrip, coordinates: coords, distanceMeters: d)
        }
    }

    var domain: CourseSegment {
        let coords = coordinates.map(\.domain)
        switch kind {
        case .tapped:    return .tapped(coordinates: coords, distanceMeters: distanceMeters)
        case .drawn:     return .drawn(coordinates: coords, distanceMeters: distanceMeters)
        case .roundTrip: return .roundTrip(coordinates: coords, distanceMeters: distanceMeters)
        }
    }
}

extension CoursePersistenceDTO.Draft {
    init(_ draft: CourseDraft) {
        self.init(
            version: CoursePersistenceDTO.currentVersion,
            entries: draft.entries.map {
                CoursePersistenceDTO.DraftEntry(
                    id: $0.id, order: $0.order, placedAtFront: $0.placedAtFront,
                    anchorID: $0.anchorID, anchorInsertsBefore: $0.anchorInsertsBefore,
                    segment: CoursePersistenceDTO.Segment($0.segment)
                )
            },
            nextOrder: draft.nextOrder
        )
    }

    var domain: CourseDraft {
        CourseDraft(
            entries: entries.map {
                CourseDraft.Entry(
                    id: $0.id, order: $0.order, placedAtFront: $0.placedAtFront,
                    anchorID: $0.anchorID, anchorInsertsBefore: $0.anchorInsertsBefore,
                    segment: $0.segment.domain
                )
            },
            nextOrder: nextOrder
        )
    }
}
