import Foundation

extension CourseCoordinate {
    /// 두 좌표 사이의 대략적 지표면 거리(미터, Haversine).
    func distanceMeters(to other: CourseCoordinate) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let hv = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(hv)))
    }

    /// 이 좌표에서 선분 a-b까지의 최단 거리(미터).
    /// 코스 규모(수 km)에서는 등장방형(equirectangular) 근사로 충분하다.
    func distanceMeters(toSegment a: CourseCoordinate, _ b: CourseCoordinate) -> Double {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(latitude * .pi / 180)
        // 자기 자신을 원점으로 한 로컬 평면(미터)
        let ax = (a.longitude - longitude) * metersPerDegreeLon
        let ay = (a.latitude - latitude) * metersPerDegreeLat
        let bx = (b.longitude - longitude) * metersPerDegreeLon
        let by = (b.latitude - latitude) * metersPerDegreeLat
        let abx = bx - ax
        let aby = by - ay
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else { return sqrt(ax * ax + ay * ay) }
        let t = max(0, min(1, -(ax * abx + ay * aby) / lengthSquared))
        let closestX = ax + t * abx
        let closestY = ay + t * aby
        return sqrt(closestX * closestX + closestY * closestY)
    }

    /// self → other 로컬 평면 벡터(미터, 동쪽/북쪽 성분)
    func headingVector(to other: CourseCoordinate) -> (dxEast: Double, dyNorth: Double) {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(latitude * .pi / 180)
        return (
            (other.longitude - longitude) * metersPerDegreeLon,
            (other.latitude - latitude) * metersPerDegreeLat
        )
    }

    /// 진행 방향(heading) 기준 오른쪽 수직으로 meters만큼 이동한 좌표
    func offset(
        rightOfHeading heading: (dxEast: Double, dyNorth: Double),
        by meters: Double
    ) -> CourseCoordinate {
        let length = sqrt(heading.dxEast * heading.dxEast + heading.dyNorth * heading.dyNorth)
        guard length > 0, meters != 0 else { return self }
        // (동, 북) 진행의 오른쪽 = (북, -동)
        let rightEast = heading.dyNorth / length
        let rightNorth = -heading.dxEast / length
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(latitude * .pi / 180)
        return CourseCoordinate(
            latitude: latitude + (meters * rightNorth) / metersPerDegreeLat,
            longitude: longitude + (meters * rightEast) / metersPerDegreeLon
        )
    }
}
