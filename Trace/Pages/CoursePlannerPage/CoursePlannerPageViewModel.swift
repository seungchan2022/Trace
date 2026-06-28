import Foundation
import Observation

enum InteractionMode: Equatable {
    case tap
    case draw
}

@MainActor
@Observable
final class CoursePlannerPageViewModel {
    private(set) var startCoordinate: CourseCoordinate?
    private(set) var destinationCoordinate: CourseCoordinate?
    private(set) var course: PlannedCourse?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var initialCameraCoordinate: CourseCoordinate?
    private(set) var interactionMode: InteractionMode = .tap
    private(set) var drawnStrokes: [[CourseCoordinate]] = []
    private(set) var strokeEntries: [StrokeEntry] = []
    private var history: [CourseSegment] = []
    private var accumulatedCoordinates: [CourseCoordinate] = []
    private var accumulatedDistance: Double = 0
    var showLocationDeniedAlert = false

    private let coursePlanningService: CoursePlanningServiceProtocol
    private let locationService: LocationServiceProtocol
    private let cameraStateStore: CameraStateStore
    private var recomputeGeneration = 0
    // 그리기 모드 진입 전 탭 상태 — 아무것도 안 그리고 복귀할 때 복원
    private var preDrawTapState: (start: CourseCoordinate?, destination: CourseCoordinate?)?

    init(
        coursePlanningService: CoursePlanningServiceProtocol,
        locationService: LocationServiceProtocol,
        cameraStateStore: CameraStateStore = CameraStateStore()
    ) {
        self.coursePlanningService = coursePlanningService
        self.locationService = locationService
        self.cameraStateStore = cameraStateStore
    }

    var isDrawingMode: Bool { interactionMode == .draw }

    var distanceText: String? {
        guard let course else { return nil }
        return String(format: "%.2f km", course.distanceMeters / 1000)
    }

    func bootstrapLocation() async {
        // 저장된 카메라가 있으면 Page에서 이미 복원했으므로 위치 요청만 하고 카메라는 건드리지 않음
        let hasRestoredCamera = cameraStateStore.restore() != nil

        do {
            let location = try await locationService.currentLocation()
            if !hasRestoredCamera {
                initialCameraCoordinate = location
            }
        } catch LocationError.denied {
            showLocationDeniedAlert = true
            if !hasRestoredCamera {
                initialCameraCoordinate = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
            }
        } catch {
            if !hasRestoredCamera {
                initialCameraCoordinate = CourseCoordinate(latitude: 37.5666, longitude: 126.9784)
            }
        }
    }

    func recenterToCurrentLocation() async -> CourseCoordinate? {
        do {
            return try await locationService.currentLocation()
        } catch {
            return nil
        }
    }

    func handleMapTap(at coordinate: CourseCoordinate) async {
        if startCoordinate == nil || destinationCoordinate != nil {
            startCoordinate = coordinate
            destinationCoordinate = nil
            course = history.isEmpty ? nil : PlannedCourse(segments: history)
            errorMessage = nil
            isLoading = false
            return
        }

        destinationCoordinate = coordinate
        await calculateCourse()
    }

    func toggleDrawingMode() {
        switch interactionMode {
        case .tap:
            // 복귀 시 복원을 위해 현재 탭 상태 저장
            preDrawTapState = (startCoordinate, destinationCoordinate)
            // 현재 탭 세션의 leg를 history에 봉인
            if let course {
                let sessionSegments = Array(course.segments.dropFirst(history.count))
                history.append(contentsOf: sessionSegments)
            }
            // history 전체 경로를 씨드로 사용 — 방향 해석기가 A→B 전체 맥락을 알아야 함
            let enterDrawCourse = history.isEmpty ? nil : PlannedCourse(segments: history)
            accumulatedCoordinates = enterDrawCourse?.coordinates ?? []
            accumulatedDistance = enterDrawCourse?.distanceMeters ?? 0
            startCoordinate = nil
            destinationCoordinate = nil
            recomputeGeneration += 1
            errorMessage = nil
            isLoading = false
            interactionMode = .draw
            course = enterDrawCourse

        case .draw:
            if !drawnStrokes.isEmpty {
                // 실제로 그린 내용이 있으면 전체 누적 경로를 단일 drawn 세그먼트로 봉인
                history = [.drawn(
                    coordinates: accumulatedCoordinates,
                    distanceMeters: accumulatedDistance
                )]
                startCoordinate = nil
                destinationCoordinate = nil
            } else {
                // 아무것도 안 그렸으면 진입 전 탭 상태 복원
                startCoordinate = preDrawTapState?.start
                destinationCoordinate = preDrawTapState?.destination
            }
            preDrawTapState = nil
            drawnStrokes = []
            strokeEntries = []
            accumulatedCoordinates = []
            accumulatedDistance = 0
            recomputeGeneration += 1
            errorMessage = nil
            interactionMode = .tap
            course = history.isEmpty ? nil : PlannedCourse(segments: history)
        }
    }

    func appendStroke(_ stroke: [CourseCoordinate]) async {
        guard stroke.count >= 2 else { return }
        drawnStrokes.append(stroke)
        recomputeGeneration += 1
        let generation = recomputeGeneration
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard generation == recomputeGeneration else { isLoading = false; return }
        await incrementalRoute(rawStroke: stroke, generation: generation)
    }

    func undoLastStroke() async {
        guard strokeEntries.popLast() != nil else { return }
        drawnStrokes.removeLast()
        recomputeGeneration += 1

        let undoHistoryCourse = history.isEmpty ? nil : PlannedCourse(segments: history)
        if strokeEntries.isEmpty {
            accumulatedCoordinates = undoHistoryCourse?.coordinates ?? []
            accumulatedDistance = undoHistoryCourse?.distanceMeters ?? 0
            course = undoHistoryCourse
            errorMessage = nil
        } else {
            // 전체 재계산 — drawnStrokes를 순회하여 재구축 (double-sampling 방지)
            recomputeGeneration += 1
            let generation = recomputeGeneration
            let savedStrokes = drawnStrokes
            strokeEntries = []
            accumulatedCoordinates = undoHistoryCourse?.coordinates ?? []
            accumulatedDistance = undoHistoryCourse?.distanceMeters ?? 0
            course = undoHistoryCourse
            errorMessage = nil

            for stroke in savedStrokes {
                await incrementalRoute(rawStroke: stroke, generation: generation)
                guard generation == recomputeGeneration else { isLoading = false; return }
            }
        }
    }

    func clear() {
        recomputeGeneration += 1
        history = []
        preDrawTapState = nil
        startCoordinate = nil
        destinationCoordinate = nil
        drawnStrokes = []
        strokeEntries = []
        accumulatedCoordinates = []
        accumulatedDistance = 0
        course = nil
        errorMessage = nil
        isLoading = false
    }

    private func calculateCourse() async {
        guard let startCoordinate, let destinationCoordinate else { return }

        recomputeGeneration += 1
        let generation = recomputeGeneration
        isLoading = true
        errorMessage = nil
        course = history.isEmpty ? nil : PlannedCourse(segments: history)

        do {
            let route = try await coursePlanningService.route(from: startCoordinate, to: destinationCoordinate)
            guard generation == recomputeGeneration else { isLoading = false; return }
            let tap = CourseSegment.tapped(
                coordinates: route.coordinates,
                distanceMeters: route.distanceMeters
            )
            course = PlannedCourse(segments: history + [tap])
        } catch CoursePlanningError.routeNotFound {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "도보 경로를 찾을 수 없습니다."
        } catch {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "경로를 계산할 수 없습니다."
        }

        isLoading = false
    }

    private func incrementalRoute(rawStroke: [CourseCoordinate], generation: Int) async {
        let sampled = DrawnPathSampler.sample(rawStroke)
        guard sampled.count >= 2 else { return }

        let attachment = StrokeDirectionResolver.resolve(
            newStroke: sampled,
            existingCourseStart: accumulatedCoordinates.first,
            existingCourseEnd: accumulatedCoordinates.last
        )
        let oriented = attachment.orientedStroke

        isLoading = true
        errorMessage = nil

        do {
            // 1) 새 스트로크 내부 구간 라우팅
            var newCoords: [CourseCoordinate] = []
            var newDistance = 0.0
            for i in 0..<(oriented.count - 1) {
                let leg = try await coursePlanningService.route(from: oriented[i], to: oriented[i + 1])
                guard generation == recomputeGeneration else { isLoading = false; return }
                newCoords.append(contentsOf: newCoords.isEmpty ? leg.coordinates : Array(leg.coordinates.dropFirst()))
                newDistance += leg.distanceMeters
            }

            // 2) 기존 경로와 연결 구간
            switch attachment.direction {
            case .initial:
                accumulatedCoordinates = newCoords
                accumulatedDistance = newDistance
            case .append:
                if let existingEnd = accumulatedCoordinates.last, let newStart = newCoords.first {
                    let connection = try await coursePlanningService.route(from: existingEnd, to: newStart)
                    guard generation == recomputeGeneration else { isLoading = false; return }
                    accumulatedCoordinates.append(contentsOf: Array(connection.coordinates.dropFirst()))
                    accumulatedDistance += connection.distanceMeters
                }
                accumulatedCoordinates.append(contentsOf: Array(newCoords.dropFirst()))
                accumulatedDistance += newDistance
            case .prepend:
                if let existingStart = accumulatedCoordinates.first, let newEnd = newCoords.last {
                    let connection = try await coursePlanningService.route(from: newEnd, to: existingStart)
                    guard generation == recomputeGeneration else { isLoading = false; return }
                    var merged = newCoords
                    merged.append(contentsOf: Array(connection.coordinates.dropFirst()))
                    merged.append(contentsOf: Array(accumulatedCoordinates.dropFirst()))
                    accumulatedDistance += connection.distanceMeters + newDistance
                    accumulatedCoordinates = merged
                }
            }

            let entry = StrokeEntry(
                orientedStroke: oriented,
                direction: attachment.direction,
                routedCoordinateCount: newCoords.count,
                routedDistance: newDistance
            )
            strokeEntries.append(entry)

            let drawn = CourseSegment.drawn(
                coordinates: accumulatedCoordinates,
                distanceMeters: accumulatedDistance
            )
            // drawn이 history 좌표를 포함한 전체 경로이므로 history를 별도로 더하지 않음
            course = PlannedCourse(segments: [drawn])
        } catch CoursePlanningError.throttled {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "요청이 많아 잠시 후 다시 시도해주세요"
            drawnStrokes.removeLast()
        } catch {
            guard generation == recomputeGeneration else { isLoading = false; return }
            errorMessage = "경로를 계산할 수 없습니다."
            drawnStrokes.removeLast()
        }
        isLoading = false
    }
}
