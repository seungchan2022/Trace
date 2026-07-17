# run-splits-audio (MVP14 사이클 2) Implementation Plan

> **완료(소급 확인):** Task 1~7 전부 구현·리뷰·검증 완료(커밋 `e5584d4`..`31dfc20`, 최종 브랜치
> 리뷰(opus) Ready to merge: Yes), 실기기 QA 진행 중 발견된 평균 페이스 시간 기준 불일치
> 버그 수정(`f306791`) 후 QA 통과(2026-07-17, 핵심 시나리오 전부 통과, 커밋 `e250c89`).
> 아래 체크박스는 실행 당시 갱신되지 않았으나 `docs/roadmap.md`의 완료 기록과 git 히스토리로
> 완료가 확인되어 소급 복원하지 않는다.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** km 스플릿 엔진(라이브·소급 공용) + 기록 상세 스플릿 표 + 러닝 음성 안내(TTS, 덕킹, 백그라운드 오디오, km 경계/상태 전환 발화)를 구현한다.

**Architecture:** Domain에 순수 스플릿 계산기(`RunSplitCalculator`)를 만들어 기록 상세가 저장 샘플로 일괄 계산한다(과거 기록 소급 포함). 음성은 port-and-adapter(`VoiceAnnouncerProtocol` ← `SpeechVoiceAnnouncer`/AVSpeechSynthesizer)로 분리하고, `RunAudioCoach`(Application)가 `RunSession`을 `withObservationTracking`으로 구독해(기존 `RunActivityController`와 동일 패턴) 상태 전환·km 경계에서 문장을 조립해 발화한다 — 세션 자체는 오디오를 모른다(스펙 §3.3 소비자 원칙). 저장 스키마 변경 없음.

**Tech Stack:** Swift 6(기본 nonisolated + UI/상태 타입 명시 `@MainActor`), SwiftUI, Observation, AVFoundation(AVSpeechSynthesizer + AVAudioSession), XCTest.

**스펙:** `docs/superpowers/specs/2026-07-15-run-experience-design.md` §3.2, §3.3, §5 — 결정 3(km 발화 = 거리+총시간+평균 페이스), 결정 4(상태 전환 발화), 결정 5(덕킹), 결정 7(모드 무관 공통).

## 플랜 단계에서 확정한 결정 (스펙 §5 이연분 종결)

- **오디오 세션 활성화 실패(통화 중 등) 시 그 발화는 건너뛴다(재시도 없음).** 재시도는 시점이 지난 값을 읽게 되고(다음 km 경계가 곧 온다), 통화 중 TTS 개입도 부적절. `docs/agent-rules/project-decisions.md`에 기록됨.
- 플랜 레벨 세부(UI 디테일급, 자동 진행): 시작 발화는 `.idle → .acquiring` 전이 시(버튼 확인 피드백 목적), 한 sync에서 여러 km 경계를 지난 극단 케이스는 최신 경계만 발화(밀린 발화 연쇄 방지), 음성은 `ko-KR` 시스템 보이스 고정.

## Global Constraints

- 브랜치: `feature/run-splits-audio` (main에서 분기, 이미 생성됨). 커밋은 `scripts/trace-commit.sh`로 경로 명시 스테이징. `git add -A`/`git push` 금지.
- 커밋 전 3종 통과 + 스탬프 갱신 필수(`docs/agent-rules/testing.md`): build/test/lint 각각 성공 후 `.git/trace-verify-{build,test,lint}.ok` touch. 테스트는 반드시 `-parallel-testing-enabled NO`, iOS 26.5 시뮬레이터 하나만 사용(세션 중 교체 금지), XcodeBuildMCP `test_sim` 금지.
- 검증 명령 (아래 각 Task의 "Run"은 이 형식을 따른다. `$SIM_UDID`는 세션 시작 시 한 번 결정):

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO \
  -only-testing:TraceTests/<TestClass> test
swiftlint
```

- force unwrap/cast/try 금지(린트 에러), IUO(`var x: T!`) 금지 — 테스트 픽스처는 `private let` + `lazy var` 필드 초기화 패턴(RunSessionTests 참고).
- 값 타입은 `Equatable, Sendable`. 도메인/DTO에 SwiftData·UIKit import 금지. 필요 없는 곳에 어노테이션을 남기지 않는다.
- 새 파일은 pbxproj 수정 불필요(fileSystemSynchronizedGroups — 폴더에 놓으면 자동 등록).
- 커밋 메시지: `tag: 한국어 제목` + 본문 3~4줄(한국어), Co-Authored-By 금지.
- **이 사이클 범위 밖(구현 금지):** 목표 설정/목표 발화(사이클 3), 음성 on/off 토글, 발화 빈도 설정, 직전 km 페이스 발화, 자동 일시정지, 잠금화면 인터랙티브 버튼, 스플릿 저장(샘플에서 파생 — 스펙 §4).

## 설계 노트 — "라이브와 소급이 같은 코드"의 해석

스플릿 *상세*(km별 시간·페이스)의 유일한 엔진은 `RunSplitCalculator`다(기록 상세 전담).
라이브 쪽 km *경계 감지*는 `Int(track.totalDistanceMeters / 1000)`의 증가 비교로 충분하다 —
결정 3에 따라 km 발화 내용은 **총시간+평균 페이스**라 구간 상세가 필요 없고, 경계의 정의
(누적 거리 k×1000 통과)는 계산기와 동일한 적산(`RunTrack`) 위에 있다. 나중에 "직전 km 페이스
발화" 트리거(스펙 §6)가 켜지면 `track.samples.map(SavedRunSample.init)`으로 라이브에서도
같은 계산기를 그대로 호출할 수 있다 — 엔진이 `[SavedRunSample]`을 입력으로 받는 이유.

거리 적산 규칙은 라이브(`RunTrack.append` + `markGap`)와 동일하게 맞춘다: **일시정지를 사이에
둔 샘플 쌍은 거리를 가산하지 않는다**(일시정지 중 샘플은 저장 자체가 안 되므로, 일시정지 구간은
항상 연속 샘플 쌍 사이에 낀다). 2026-07-14 실기기 왕복 검증에서 저장 샘플 재계산이 화면 표시값과
일치함이 확인돼 있으므로, 라이브 경계(k km 발화 순간)와 소급 표의 경계는 같은 지점에 떨어진다.

## File Structure

- Create: `Trace/Domain/RunTracking/Entity/RunSplit.swift` — `RunSplit`/`RunSplitPartial`/`RunSplitResult` 값 타입 + `RunSplitCalculator` 순수 계산기
- Create: `Trace/Domain/RunTracking/Protocol/VoiceAnnouncerProtocol.swift` — 발화 포트
- Create: `Trace/Infrastructure/Audio/SpeechVoiceAnnouncer.swift` — AVSpeechSynthesizer + AVAudioSession 어댑터 (새 폴더 `Infrastructure/Audio`)
- Create: `Trace/Application/RunTracking/RunAnnouncementBuilder.swift` — 발화 문구 조립(순수)
- Create: `Trace/Application/RunTracking/RunAudioCoach.swift` — 세션 구독 → 발화 소비자
- Modify: `Trace/Application/RunTracking/RunSession.swift` — `summaryActiveElapsedSeconds` 계산 프로퍼티 1개 추가
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift` — 기록 상세에 스플릿 표
- Modify: `Config/Trace-Info.plist` — `UIBackgroundModes`에 `audio` 추가
- Modify: `Trace/App/DependencyContainer.swift`, `Trace/App/TraceApp.swift` — 코치 배선
- Test: `TraceTests/RunSplitCalculatorTests.swift`, `TraceTests/RunAnnouncementBuilderTests.swift`, `TraceTests/RunAudioCoachTests.swift`

---

### Task 1: 백그라운드 오디오 스파이크 (Background Mode + 어댑터 + 실기기 확인)

이번 MVP의 핵심 미지수 — "화면 꺼진 채 음악 위에서 TTS가 나오고 볼륨이 복원되는가" — 를
본 구현 전에 실기기로 확인한다(스펙 §5). 어댑터는 버리는 코드가 아니라 실제 산출물이고,
DEBUG 전용 트리거 버튼만 Task 6에서 제거한다.

**Files:**
- Modify: `Config/Trace-Info.plist`
- Create: `Trace/Domain/RunTracking/Protocol/VoiceAnnouncerProtocol.swift`
- Create: `Trace/Infrastructure/Audio/SpeechVoiceAnnouncer.swift`
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift` (DEBUG 스파이크 버튼)

**Interfaces:**
- Produces: `VoiceAnnouncerProtocol`(`@MainActor`, `func announce(_ text: String)`), `SpeechVoiceAnnouncer`(구현체) — Task 5·6이 소비

**어댑터에 단위 테스트를 쓰지 않는 이유:** AVSpeechSynthesizer/AVAudioSession은 하드웨어
부수효과 자체가 본체라 시뮬레이터 단위 테스트가 무의미하고(발화·덕킹은 실기기에서만 검증 가능),
결정 로직은 전부 프로토콜 뒤의 소비자(코치)에 있어 페이크로 검증한다(스펙 §5).
`RunActivityController`(ActivityKit 어댑터 성격)도 같은 이유로 단위 테스트가 없는 선례.

- [ ] **Step 1: Info.plist에 audio Background Mode 추가**

`Config/Trace-Info.plist`의 `UIBackgroundModes` 배열을 다음으로 수정:

```xml
    <key>UIBackgroundModes</key>
    <array>
        <string>location</string>
        <string>audio</string>
    </array>
```

- [ ] **Step 2: 발화 포트 프로토콜 작성**

`Trace/Domain/RunTracking/Protocol/VoiceAnnouncerProtocol.swift` 생성:

```swift
import Foundation

/// 음성 안내 포트 — Domain은 AVFoundation을 모른다(스펙 §3.3).
/// 발화는 fire-and-forget: 호출자는 완료를 기다리지 않고, 직렬화(큐)는 구현체 책임이다.
@MainActor
protocol VoiceAnnouncerProtocol {
    func announce(_ text: String)
}
```

- [ ] **Step 3: AVSpeechSynthesizer 어댑터 작성**

`Trace/Infrastructure/Audio/SpeechVoiceAnnouncer.swift` 생성:

```swift
import AVFoundation

/// VoiceAnnouncer의 AVSpeechSynthesizer 어댑터.
/// 오디오 세션은 발화 묶음 동안만 활성화(.playback + .duckOthers)하고, 큐가 소진되는 시점에만
/// .notifyOthersOnDeactivation으로 비활성화해 음악 볼륨을 복원한다 — 연속 발화(km 경계+상태 전환
/// 동시)에서 볼륨이 복원됐다 다시 내려가는 플랩을 막는다(스펙 §3.3).
/// 세션 활성화 실패(통화 중 등) 시 그 발화는 건너뛴다(재시도 없음 — 플랜 결정, project-decisions.md).
@MainActor
final class SpeechVoiceAnnouncer: NSObject, VoiceAnnouncerProtocol {
    private let synthesizer = AVSpeechSynthesizer()
    /// 큐에 남아 있는 발화 수 — 0이 되는 시점(큐 소진)에만 세션을 비활성화한다
    private var pendingCount = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func announce(_ text: String) {
        if pendingCount == 0 {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try audioSession.setActive(true)
            } catch {
                return // 활성화 실패(통화 중 등) — 이번 발화는 건너뛴다
            }
        }
        pendingCount += 1
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        synthesizer.speak(utterance)
    }

    private func utteranceEnded() {
        pendingCount = max(0, pendingCount - 1)
        guard pendingCount == 0 else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension SpeechVoiceAnnouncer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.utteranceEnded() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.utteranceEnded() }
    }
}
```

주의: Swift 6에서 delegate 적합성에 isolation/Sendable 경고가 나면 `@preconcurrency import AVFoundation`으로
전환한다(`RunActivityController`의 `@preconcurrency import ActivityKit` 선례). delegate 콜백 스레드는
보장이 없으므로 `nonisolated` + `Task { @MainActor in }` 홉을 유지한다(CoreLocationService 선례).

- [ ] **Step 4: 트래킹 화면에 DEBUG 스파이크 버튼 추가**

실기기 시나리오를 충실히 재현하려면 **러닝 중(백그라운드 location으로 앱이 살아 있는 상태)**
잠금 후 발화가 나와야 한다. `RunStatsPanel`(트래킹 중 패널)에 DEBUG 전용 "10초 후 발화" 버튼을
넣는다 — 탭 → 화면 잠금 → 10초 뒤 발화 확인. `Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift`의
`RunStatsPanel`에 추가:

```swift
    // struct RunStatsPanel 프로퍼티에 추가
    #if DEBUG
    // 사이클 2 오디오 스파이크 전용 — 배선(Task 6)에서 제거
    @State private var spikeAnnouncer = SpeechVoiceAnnouncer()
    #endif
```

`body`의 `VStack(spacing: 14)` 안, `HStack(spacing: 12) { pauseResumeButton; endButton }` 위에 추가:

```swift
            #if DEBUG
            Button("10초 후 발화 (스파이크)") {
                let announcer = spikeAnnouncer
                Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    announcer.announce("백그라운드 오디오 테스트. 지금 음악 볼륨이 줄었다가 다시 돌아오면 성공입니다.")
                }
            }
            .font(DesignToken.Typography.chip)
            #endif
```

- [ ] **Step 5: 빌드 + 전체 테스트 + 린트**

Run:

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO test
swiftlint
```

Expected: 빌드 성공, 기존 테스트 전부 PASS(이번 태스크는 기존 로직 무변경), 린트 위반 0.

- [ ] **Step 6: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 백그라운드 오디오 스파이크 — TTS 어댑터 + audio Background Mode

- VoiceAnnouncerProtocol 포트와 SpeechVoiceAnnouncer(AVSpeechSynthesizer) 어댑터를 추가한다
- 오디오 세션은 발화 순간만 .playback+.duckOthers로 활성화하고 큐 소진 시 복원한다
- UIBackgroundModes에 audio를 추가해 화면 꺼짐 발화를 가능하게 한다
- 트래킹 화면에 DEBUG 전용 지연 발화 버튼을 넣어 실기기 스파이크를 준비한다" \
  -- Config/Trace-Info.plist Trace/Domain/RunTracking/Protocol/VoiceAnnouncerProtocol.swift \
     Trace/Infrastructure/Audio/SpeechVoiceAnnouncer.swift \
     Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift
```

- [ ] **Step 7: 실기기 스파이크 확인 요청 (블로킹 체크포인트)**

사용자에게 실기기 절차를 안내하고 결과를 기다린다:

1. 실기기에서 앱 실행, 음악 재생 시작(Apple Music 등)
2. 러닝 시작 → 트래킹 화면 진입(GPS 확보)
3. "10초 후 발화 (스파이크)" 버튼 탭 → 즉시 화면 잠금
4. 10초 뒤 잠긴 화면에서: 음악 볼륨이 낮아지고 → 안내 음성이 나오고 → 음악 볼륨이 복원되는지 확인

**통과 기준:** 화면 꺼진 채 발화가 들리고, 덕킹·복원이 동작한다.
**실패 시:** Task 4~6(오디오 본 구현)에 진입하지 말고 멈춘다 — 세션 수명주기 설계(발화 순간만
활성화)를 재검토해야 한다(스펙 §5: 산출물 없이 되돌릴 수 있는 지점). Task 2~3(스플릿)은
오디오와 무관하므로 스파이크 결과를 기다리는 동안 진행해도 된다.

---

### Task 2: RunSplitCalculator — km 스플릿 엔진 (Domain 순수 로직)

**Files:**
- Create: `Trace/Domain/RunTracking/Entity/RunSplit.swift`
- Test: `TraceTests/RunSplitCalculatorTests.swift`

**Interfaces:**
- Consumes: `SavedRunSample`(기존 — `timestamp`/`coordinate`), `RunPauseInterval`(기존 — `start`/`end`), `CourseCoordinate.distanceMeters(to:)`(기존)
- Produces: `RunSplit { index: Int, durationSeconds: TimeInterval, paceSecondsPerKm: Double }`, `RunSplitPartial { index: Int, distanceMeters: Double, durationSeconds: TimeInterval }`, `RunSplitResult { completed: [RunSplit], partial: RunSplitPartial? }`, `RunSplitCalculator.splits(samples:pauses:) -> RunSplitResult`, `RunSplitCalculator.splitDistanceMeters: Double` — Task 3(표)·Task 5(코치의 km 상수)가 소비

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/RunSplitCalculatorTests.swift` 생성:

```swift
import XCTest
@testable import Trace

final class RunSplitCalculatorTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    /// 북쪽으로 meters만큼 이동한 지점의 t초 시점 샘플 (위도 1도 ≈ 111,320m)
    private func sample(t: TimeInterval, meters: Double) -> SavedRunSample {
        SavedRunSample(
            timestamp: base.addingTimeInterval(t),
            latitude: 37.5666 + meters / 111_320.0,
            longitude: 126.9784,
            altitudeMeters: 10,
            speedMetersPerSecond: 3
        )
    }

    private func pause(from: TimeInterval, to: TimeInterval) -> RunPauseInterval {
        RunPauseInterval(start: base.addingTimeInterval(from), end: base.addingTimeInterval(to))
    }

    func test_빈샘플과_단일샘플은_빈결과() {
        XCTAssertEqual(RunSplitCalculator.splits(samples: [], pauses: []), .empty)
        XCTAssertEqual(
            RunSplitCalculator.splits(samples: [sample(t: 0, meters: 0)], pauses: []),
            .empty
        )
    }

    func test_1km미만은_미완성구간만() {
        // 500m를 150초에 (5분/km 페이스)
        let samples = stride(from: 0.0, through: 500, by: 100).map {
            sample(t: $0 * 0.3, meters: $0)
        }
        let result = RunSplitCalculator.splits(samples: samples, pauses: [])
        XCTAssertTrue(result.completed.isEmpty)
        let partial = try XCTUnwrap(result.partial)
        XCTAssertEqual(partial.index, 1)
        XCTAssertEqual(partial.distanceMeters, 500, accuracy: 5)
        XCTAssertEqual(partial.durationSeconds, 150, accuracy: 2)
    }

    func test_일정속도_2km는_같은시간의_스플릿2개() {
        // 100m/30초 간격으로 2,050m (5분/km 일정 속도)
        let samples = stride(from: 0.0, through: 2050, by: 50).map {
            sample(t: $0 * 0.3, meters: $0)
        }
        let result = RunSplitCalculator.splits(samples: samples, pauses: [])
        XCTAssertEqual(result.completed.count, 2)
        XCTAssertEqual(result.completed[0].index, 1)
        XCTAssertEqual(result.completed[0].durationSeconds, 300, accuracy: 3)
        XCTAssertEqual(result.completed[1].index, 2)
        XCTAssertEqual(result.completed[1].durationSeconds, 300, accuracy: 3)
        // 완성 구간의 페이스는 구간 시간과 같다(정확히 1km이므로)
        XCTAssertEqual(result.completed[0].paceSecondsPerKm, result.completed[0].durationSeconds)
        let partial = try XCTUnwrap(result.partial)
        XCTAssertEqual(partial.distanceMeters, 50, accuracy: 5)
    }

    func test_경계통과시각은_쌍안에서_거리비례로_보간된다() {
        // 950m까지 5분/km로 온 뒤, 마지막 쌍(900→1100m)이 60초 — 경계(1000m)는 쌍의 절반 지점
        var samples = stride(from: 0.0, through: 900, by: 100).map {
            sample(t: $0 * 0.3, meters: $0)
        }
        samples.append(sample(t: 900 * 0.3 + 60, meters: 1100))
        let result = RunSplitCalculator.splits(samples: samples, pauses: [])
        XCTAssertEqual(result.completed.count, 1)
        // 270초(900m 도달) + 60초의 절반 = 300초 부근
        XCTAssertEqual(result.completed[0].durationSeconds, 300, accuracy: 5)
    }

    func test_일시정지구간은_거리도_시간도_제외된다() {
        // 600m(t=0~180) → 일시정지 300초(t=180~480, 제자리) → 600m(t=480~660)
        var samples = stride(from: 0.0, through: 600, by: 100).map {
            sample(t: $0 * 0.3, meters: $0)
        }
        samples.append(sample(t: 480, meters: 600)) // 재개 직후 첫 샘플(제자리)
        samples.append(contentsOf: stride(from: 700.0, through: 1200, by: 100).map {
            sample(t: 480 + ($0 - 600) * 0.3, meters: $0)
        })
        let pauses = [pause(from: 180, to: 480)]
        let result = RunSplitCalculator.splits(samples: samples, pauses: pauses)
        XCTAssertEqual(result.completed.count, 1)
        // 1km 경계는 활동 시간 300초 지점 — 일시정지 300초가 끼어도 구간 시간은 300초
        XCTAssertEqual(result.completed[0].durationSeconds, 300, accuracy: 5)
        let partial = try XCTUnwrap(result.partial)
        XCTAssertEqual(partial.distanceMeters, 200, accuracy: 5)
        XCTAssertEqual(partial.durationSeconds, 60, accuracy: 5)
    }

    func test_한쌍이_여러경계를_넘으면_전부_보간된다() {
        // GPS 공백: 0m → 2,500m 단일 쌍이 750초 (일정 속도 가정으로 보간)
        let samples = [sample(t: 0, meters: 0), sample(t: 750, meters: 2500)]
        let result = RunSplitCalculator.splits(samples: samples, pauses: [])
        XCTAssertEqual(result.completed.count, 2)
        XCTAssertEqual(result.completed[0].durationSeconds, 300, accuracy: 5)
        XCTAssertEqual(result.completed[1].durationSeconds, 300, accuracy: 5)
        let partial = try XCTUnwrap(result.partial)
        XCTAssertEqual(partial.distanceMeters, 500, accuracy: 10)
    }

    func test_과거기록처럼_일시정지가_없으면_빈배열로_동작한다() {
        let samples = stride(from: 0.0, through: 1100, by: 100).map {
            sample(t: $0 * 0.3, meters: $0)
        }
        let result = RunSplitCalculator.splits(samples: samples, pauses: [])
        XCTAssertEqual(result.completed.count, 1)
    }
}
```

주의: `try XCTUnwrap`을 쓰는 테스트 메서드는 `throws`로 선언한다 (`func test_...() throws`).
위 코드에서 `XCTUnwrap`을 쓰는 4개 메서드에 `throws`를 붙일 것.

- [ ] **Step 2: 실패 확인**

Run:

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO \
  -only-testing:TraceTests/RunSplitCalculatorTests test
```

Expected: 컴파일 실패 — "cannot find 'RunSplitCalculator' in scope"

- [ ] **Step 3: 최소 구현**

`Trace/Domain/RunTracking/Entity/RunSplit.swift` 생성:

```swift
import Foundation

/// 완성된 1km 구간 — 시간은 활동 시간(일시정지 제외) 기준(스펙 §3.2).
struct RunSplit: Equatable, Sendable {
    /// 1부터 시작하는 km 번호
    let index: Int
    let durationSeconds: TimeInterval

    /// 정확히 1km 구간이므로 페이스(초/km) = 구간 시간
    var paceSecondsPerKm: Double { durationSeconds }
}

/// 마지막 미완성 구간(1km 미만 잔여)
struct RunSplitPartial: Equatable, Sendable {
    let index: Int
    let distanceMeters: Double
    let durationSeconds: TimeInterval
}

struct RunSplitResult: Equatable, Sendable {
    let completed: [RunSplit]
    let partial: RunSplitPartial?

    static let empty = RunSplitResult(completed: [], partial: nil)
}

/// km 스플릿 일괄 계산 — 저장 샘플 + 일시정지 구간에서 km별 활동 시간을 파생한다(스펙 §3.2).
/// 저장된 과거 기록(일시정지 없음 = 빈 배열)에도 그대로 소급 적용된다.
/// 거리 적산 규칙은 라이브(RunTrack)와 동일: 일시정지를 사이에 둔 샘플 쌍은 거리를 가산하지 않는다.
enum RunSplitCalculator {
    static let splitDistanceMeters: Double = 1000

    static func splits(samples: [SavedRunSample], pauses: [RunPauseInterval]) -> RunSplitResult {
        guard samples.count >= 2, let first = samples.first else { return .empty }

        var completed: [RunSplit] = []
        var cumulativeDistance: Double = 0
        var lastBoundaryActiveSeconds: TimeInterval = 0
        var nextBoundary = splitDistanceMeters

        for (previous, sample) in zip(samples, samples.dropFirst()) {
            // 일시정지가 사이에 낀 쌍은 이동으로 치지 않는다(라이브 markGap과 동일 규칙)
            let straddlesPause = pauses.contains {
                $0.start < sample.timestamp && $0.end > previous.timestamp
            }
            guard straddlesPause == false else { continue }
            let step = previous.coordinate.distanceMeters(to: sample.coordinate)
            guard step > 0 else { continue }

            let stepStartDistance = cumulativeDistance
            cumulativeDistance += step

            while cumulativeDistance >= nextBoundary {
                // 경계 통과 시각: 쌍 안에서 거리 비례 선형 보간 → 활동 시간으로 환산.
                // GPS 공백 쌍(장시간·장거리)도 같은 보간을 적용한다 — 일정 속도 가정의 근사.
                let fraction = (nextBoundary - stepStartDistance) / step
                let crossingTimestamp = previous.timestamp.addingTimeInterval(
                    sample.timestamp.timeIntervalSince(previous.timestamp) * fraction
                )
                let crossingActive = activeSeconds(
                    at: crossingTimestamp, start: first.timestamp, pauses: pauses
                )
                completed.append(RunSplit(
                    index: completed.count + 1,
                    durationSeconds: crossingActive - lastBoundaryActiveSeconds
                ))
                lastBoundaryActiveSeconds = crossingActive
                nextBoundary += splitDistanceMeters
            }
        }

        var partial: RunSplitPartial?
        let remainder = cumulativeDistance - Double(completed.count) * splitDistanceMeters
        if remainder > 0, let last = samples.last {
            partial = RunSplitPartial(
                index: completed.count + 1,
                distanceMeters: remainder,
                durationSeconds: activeSeconds(at: last.timestamp, start: first.timestamp, pauses: pauses)
                    - lastBoundaryActiveSeconds
            )
        }
        return RunSplitResult(completed: completed, partial: partial)
    }

    /// t 시점까지의 활동 시간 = 벽시계 경과 − [start, t]와 겹치는 일시정지 합
    private static func activeSeconds(
        at t: Date, start: Date, pauses: [RunPauseInterval]
    ) -> TimeInterval {
        let pausedOverlap = pauses.reduce(0.0) { total, pause in
            let overlapStart = max(pause.start, start)
            let overlapEnd = min(pause.end, t)
            return total + max(0, overlapEnd.timeIntervalSince(overlapStart))
        }
        return t.timeIntervalSince(start) - pausedOverlap
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: Step 2와 동일 명령.
Expected: `Test Suite 'RunSplitCalculatorTests' passed` — 7개 테스트 전부 PASS.

- [ ] **Step 5: 커밋**

```bash
scripts/trace-commit.sh -m "feat: km 스플릿 엔진 — 저장 샘플에서 구간 시간·페이스 파생

- RunSplitCalculator가 샘플 스트림+일시정지 구간에서 km별 활동 시간을 일괄 계산한다
- 경계 통과 시각은 샘플 쌍 안에서 거리 비례 선형 보간으로 정한다
- 일시정지를 사이에 둔 쌍은 라이브(markGap)와 동일하게 거리를 가산하지 않는다
- 과거 기록(일시정지 없음)에도 빈 배열 입력으로 그대로 소급 적용된다" \
  -- Trace/Domain/RunTracking/Entity/RunSplit.swift TraceTests/RunSplitCalculatorTests.swift
```

---

### Task 3: 기록 상세 스플릿 표

**Files:**
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift`

**Interfaces:**
- Consumes: `RunSplitCalculator.splits(samples:pauses:)`, `RunSplitResult`/`RunSplit`/`RunSplitPartial` (Task 2), `RunPaceFormatter.string(secondsPerKm:)`(기존), `loadedRun: SavedRun?`(기존 상태)

- [ ] **Step 1: RunRecordDetailView에 스플릿 섹션 추가**

`RunRecordDetailView.body`의 `VStack(spacing: 0)`을 다음으로 교체(지도는 유지, 숫자 영역을
스크롤로 감싸고 스플릿 섹션 추가):

```swift
    var body: some View {
        VStack(spacing: 0) {
            detailMap
            ScrollView {
                statsGrid
                    .padding(DesignToken.Size.sheetPadding)
                if let loadedRun {
                    RunSplitsSection(result: RunSplitCalculator.splits(
                        samples: loadedRun.samples, pauses: loadedRun.pauses
                    ))
                }
            }
        }
        .navigationTitle(summary.startedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadedRun = await viewModel.loadRun(id: summary.id)
            loadFinished = true
        }
    }
```

같은 파일 끝에 섹션 뷰 추가:

```swift
/// km 스플릿 표 — 완성 구간은 1km 페이스(=구간 시간), 마지막 미완성 구간은 실거리 환산 페이스(스펙 §3.2)
private struct RunSplitsSection: View {
    let result: RunSplitResult

    var body: some View {
        if result.completed.isEmpty == false || result.partial != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("킬로미터별 페이스")
                    .font(DesignToken.Typography.sectionLabel)
                    .foregroundStyle(DesignToken.Color.ink2)
                ForEach(result.completed, id: \.index) { split in
                    row(
                        label: "\(split.index) km",
                        pace: RunPaceFormatter.string(secondsPerKm: split.paceSecondsPerKm)
                    )
                }
                if let partial = result.partial {
                    row(
                        label: String(format: "%.2f km", partial.distanceMeters / 1000),
                        pace: RunPaceFormatter.string(secondsPerKm: partialPace(partial))
                    )
                }
            }
            .padding(.horizontal, DesignToken.Size.sheetPadding)
            .padding(.bottom, DesignToken.Size.sheetPadding)
        }
    }

    private func partialPace(_ partial: RunSplitPartial) -> Double? {
        guard partial.distanceMeters > 0 else { return nil }
        return partial.durationSeconds / (partial.distanceMeters / 1000)
    }

    private func row(label: String, pace: String) -> some View {
        HStack {
            Text(label)
                .font(DesignToken.Typography.segmentRowTitle)
                .foregroundStyle(DesignToken.Color.ink)
            Spacer()
            Text(pace)
                .font(DesignToken.Typography.segmentRowDistance)
                .monospacedDigit()
                .foregroundStyle(DesignToken.Color.ink)
        }
    }
}
```

- [ ] **Step 2: 빌드 + 전체 테스트 + 시뮬레이터 육안 확인**

Run:

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO test
swiftlint
```

Expected: 전부 PASS, 린트 0. 육안 확인: 시뮬레이터에서 앱 실행 → Features > Location >
City Run 켜고 러닝 시작 → 1~2분 트래킹 → 종료 → 기록 목록 → 상세 진입 →
"킬로미터별 페이스" 섹션에 행이 나오는지(1km 미만이면 미완성 행 1개) 확인.
**소급 확인**: 이전 사이클에서 저장된 기존 기록이 시뮬레이터에 있으면 그 상세에도 표가 나오는지 확인.

- [ ] **Step 3: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 기록 상세에 킬로미터별 페이스 표 추가

- 저장 샘플+일시정지 구간을 RunSplitCalculator로 일괄 계산해 표로 보여준다
- 마지막 미완성 구간은 실거리(소수 km)와 환산 페이스로 표시한다
- 스플릿은 저장하지 않고 상세 진입 시 파생한다(스펙 §4)
- 과거 기록에도 빈 일시정지 배열로 그대로 소급 적용된다" \
  -- Trace/Pages/RunPage/UIComponent/RunPage+HistoryComponent.swift
```

---

### Task 4: RunAnnouncementBuilder — 발화 문구 조립 (순수)

**Files:**
- Create: `Trace/Application/RunTracking/RunAnnouncementBuilder.swift`
- Test: `TraceTests/RunAnnouncementBuilderTests.swift`

**Interfaces:**
- Produces: `RunAnnouncementBuilder.start/pause/resume: String`, `kilometer(km:totalSeconds:averagePaceSecondsPerKm:) -> String`, `finish(distanceMeters:totalSeconds:averagePaceSecondsPerKm:) -> String` — Task 5(코치)가 소비

- [ ] **Step 1: 실패하는 테스트 작성**

`TraceTests/RunAnnouncementBuilderTests.swift` 생성:

```swift
import XCTest
@testable import Trace

final class RunAnnouncementBuilderTests: XCTestCase {
    func test_상태전환_고정문구() {
        XCTAssertEqual(RunAnnouncementBuilder.start, "러닝 시작")
        XCTAssertEqual(RunAnnouncementBuilder.pause, "일시정지")
        XCTAssertEqual(RunAnnouncementBuilder.resume, "재개합니다")
    }

    func test_km경계_문구는_거리_총시간_평균페이스() {
        let text = RunAnnouncementBuilder.kilometer(
            km: 3, totalSeconds: 1110, averagePaceSecondsPerKm: 370
        )
        XCTAssertEqual(text, "3킬로미터. 총 시간 18분 30초. 평균 페이스 6분 10초")
    }

    func test_km경계_페이스없으면_절생략() {
        let text = RunAnnouncementBuilder.kilometer(
            km: 1, totalSeconds: 300, averagePaceSecondsPerKm: nil
        )
        XCTAssertEqual(text, "1킬로미터. 총 시간 5분")
    }

    func test_종료_문구는_총거리_시간_평균페이스() {
        let text = RunAnnouncementBuilder.finish(
            distanceMeters: 5200, totalSeconds: 1900, averagePaceSecondsPerKm: 365
        )
        XCTAssertEqual(text, "러닝 종료. 총 5.2킬로미터, 31분 40초, 평균 페이스 6분 5초")
    }

    func test_종료_정수km는_소수점없이_읽는다() {
        let text = RunAnnouncementBuilder.finish(
            distanceMeters: 5000, totalSeconds: 1800, averagePaceSecondsPerKm: 360
        )
        XCTAssertEqual(text, "러닝 종료. 총 5킬로미터, 30분, 평균 페이스 6분")
    }

    func test_시간읽기_시간분초_조합() {
        XCTAssertEqual(RunAnnouncementBuilder.spokenDuration(45), "45초")
        XCTAssertEqual(RunAnnouncementBuilder.spokenDuration(300), "5분")
        XCTAssertEqual(RunAnnouncementBuilder.spokenDuration(1110), "18분 30초")
        XCTAssertEqual(RunAnnouncementBuilder.spokenDuration(3725), "1시간 2분 5초")
        XCTAssertEqual(RunAnnouncementBuilder.spokenDuration(0), "0초")
    }

    func test_페이스읽기_비정상값은_nil() {
        XCTAssertEqual(RunAnnouncementBuilder.spokenPace(370), "6분 10초")
        XCTAssertNil(RunAnnouncementBuilder.spokenPace(nil))
        XCTAssertNil(RunAnnouncementBuilder.spokenPace(0))
        XCTAssertNil(RunAnnouncementBuilder.spokenPace(3600)) // 60분/km 초과는 표시 규칙과 동일하게 무효
    }
}
```

- [ ] **Step 2: 실패 확인**

Run:

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO \
  -only-testing:TraceTests/RunAnnouncementBuilderTests test
```

Expected: 컴파일 실패 — "cannot find 'RunAnnouncementBuilder' in scope"

- [ ] **Step 3: 최소 구현**

`Trace/Application/RunTracking/RunAnnouncementBuilder.swift` 생성:

```swift
import Foundation

/// 발화 문구 조립 — 순수 문자열 로직(스펙 §3.3 초안 문구).
/// 표시용 포맷터(RunPaceFormatter 등)와 달리 소리 내어 읽는 한국어 문장을 만든다.
enum RunAnnouncementBuilder {
    static let start = "러닝 시작"
    static let pause = "일시정지"
    static let resume = "재개합니다"

    /// "3킬로미터. 총 시간 18분 30초. 평균 페이스 6분 10초"
    static func kilometer(km: Int, totalSeconds: TimeInterval, averagePaceSecondsPerKm: Double?) -> String {
        var text = "\(km)킬로미터. 총 시간 \(spokenDuration(totalSeconds))"
        if let pace = spokenPace(averagePaceSecondsPerKm) {
            text += ". 평균 페이스 \(pace)"
        }
        return text
    }

    /// "러닝 종료. 총 5.2킬로미터, 31분 40초, 평균 페이스 6분 5초"
    static func finish(distanceMeters: Double, totalSeconds: TimeInterval, averagePaceSecondsPerKm: Double?) -> String {
        var text = "러닝 종료. 총 \(spokenDistance(distanceMeters)), \(spokenDuration(totalSeconds))"
        if let pace = spokenPace(averagePaceSecondsPerKm) {
            text += ", 평균 페이스 \(pace)"
        }
        return text
    }

    /// 5200 → "5.2킬로미터", 5000 → "5킬로미터" (0.1km 반올림, 정수면 소수점 생략)
    static func spokenDistance(_ meters: Double) -> String {
        let roundedKm = (meters / 100).rounded() / 10
        if roundedKm == roundedKm.rounded() {
            return "\(Int(roundedKm))킬로미터"
        }
        return String(format: "%.1f킬로미터", roundedKm)
    }

    /// 1110 → "18분 30초", 3725 → "1시간 2분 5초", 300 → "5분", 45 → "45초"
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours)시간") }
        if minutes > 0 { parts.append("\(minutes)분") }
        if secs > 0 || parts.isEmpty { parts.append("\(secs)초") }
        return parts.joined(separator: " ")
    }

    /// 초/km → "6분 10초". nil·0 이하·60분/km 이상은 nil(문장에서 절 생략 — 표시 규칙과 동일 경계)
    static func spokenPace(_ secondsPerKm: Double?) -> String? {
        guard let pace = secondsPerKm, pace > 0, pace < 3600 else { return nil }
        return spokenDuration(pace)
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: Step 2와 동일 명령.
Expected: `Test Suite 'RunAnnouncementBuilderTests' passed` — 7개 테스트 전부 PASS.

- [ ] **Step 5: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 러닝 발화 문구 조립기 추가

- km 경계(거리+총시간+평균 페이스)와 종료 요약 문장을 조립한다
- 시간·페이스를 한국어로 읽는 spokenDuration/spokenPace를 제공한다
- 페이스가 무효(nil·0 이하·60분/km 이상)면 해당 절을 생략한다
- 상태 전환(시작/일시정지/재개) 고정 문구를 함께 정의한다" \
  -- Trace/Application/RunTracking/RunAnnouncementBuilder.swift \
     TraceTests/RunAnnouncementBuilderTests.swift
```

---

### Task 5: RunAudioCoach — 세션 구독 발화 소비자 (+ RunSession 최종 활동 시간 노출)

**Files:**
- Modify: `Trace/Application/RunTracking/RunSession.swift` (계산 프로퍼티 1개 추가)
- Create: `Trace/Application/RunTracking/RunAudioCoach.swift`
- Test: `TraceTests/RunAudioCoachTests.swift`

**Interfaces:**
- Consumes: `RunSession`(기존 — `state`/`track`/`activeElapsedSeconds()`/`pause()`/`resume()`/`finish()`), `VoiceAnnouncerProtocol`(Task 1), `RunAnnouncementBuilder`(Task 4), `RunSplitCalculator.splitDistanceMeters`(Task 2)
- Produces: `RunAudioCoach(session:announcer:)`, `startObserving()`, `sync()`(internal — 테스트 진입점), `RunSession.summaryActiveElapsedSeconds: TimeInterval?` — Task 6(배선)이 소비

- [ ] **Step 1: RunSession에 최종 활동 시간 프로퍼티 추가**

종료 발화·요약은 "지금" 기준이 아니라 **종료 시각 기준으로 고정된** 활동 시간이 필요하다
(`activeElapsedSeconds()`는 summary 상태에서도 계속 자란다). `RunSession.swift`의
`displayTimerStart` 프로퍼티 아래에 추가:

```swift
    /// 종료 시각 기준으로 고정된 최종 활동 시간 — summary 상태에서만 non-nil.
    /// activeElapsedSeconds()는 now 기준이라 종료 후에도 계속 자란다 — 종료 발화·요약용은 이 값.
    var summaryActiveElapsedSeconds: TimeInterval? {
        guard let startedAt, let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt) - totalPausedSeconds(now: endedAt)
    }
```

- [ ] **Step 2: 실패하는 테스트 작성**

`TraceTests/RunAudioCoachTests.swift` 생성. 픽스처는 `RunSessionTests`의
`MockRunLocationStream`/`MockRunRecordRepository`(같은 테스트 타깃)를 재사용하고, 코치의
결정 로직은 관찰 콜백을 기다리지 않고 `sync()`를 직접 호출해 결정적으로 검증한다:

```swift
import XCTest
@testable import Trace

@MainActor
final class RunAudioCoachTests: XCTestCase {
    private let stream = MockRunLocationStream()
    private let recordRepository = MockRunRecordRepository()
    private lazy var session = RunSession(locationStream: stream, recordRepository: recordRepository)
    private let announcer = FakeVoiceAnnouncer()
    private lazy var coach = RunAudioCoach(session: session, announcer: announcer)

    private func sample(at date: Date, metersNorth: Double = 0) -> RunSample {
        RunSample(
            timestamp: date,
            latitude: 37.5666 + metersNorth / 111_320.0,
            longitude: 126.9784,
            altitudeMeters: 10,
            speedMetersPerSecond: 3,
            horizontalAccuracyMeters: 5,
            verticalAccuracyMeters: 5
        )
    }

    /// 조건이 참이 될 때까지 짧은 간격으로 폴링한다(RunSessionTests와 동일 패턴)
    private func waitUntil(
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while condition() == false {
            if Date() >= deadline {
                XCTFail("timed out waiting for condition", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// 시작 → 첫 샘플 수용(tracking 진입)까지 진행하고 발화 로그를 비운다
    private func startTracking() async {
        await session.start()
        coach.sync()
        stream.yield(sample(at: Date()))
        await waitUntil { session.state == .tracking }
        coach.sync()
        announcer.announced.removeAll()
    }

    func test_시작하면_러닝시작_발화() async {
        await session.start()
        coach.sync()
        XCTAssertEqual(announcer.announced, ["러닝 시작"])
    }

    func test_일시정지와_재개_발화() async {
        await startTracking()
        session.pause()
        coach.sync()
        session.resume()
        coach.sync()
        XCTAssertEqual(announcer.announced, ["일시정지", "재개합니다"])
    }

    func test_km경계를_넘으면_한번만_발화() async {
        await startTracking()
        let start = Date()
        stream.yield(sample(at: start.addingTimeInterval(300), metersNorth: 1005))
        await waitUntil { session.track.totalDistanceMeters > 1000 }
        coach.sync()
        XCTAssertEqual(announcer.announced.count, 1)
        XCTAssertTrue(announcer.announced[0].hasPrefix("1킬로미터"))

        // 같은 km 안에서 추가 샘플 — 중복 발화 없음
        stream.yield(sample(at: start.addingTimeInterval(310), metersNorth: 1020))
        await waitUntil { session.track.totalDistanceMeters > 1015 }
        coach.sync()
        XCTAssertEqual(announcer.announced.count, 1)
    }

    func test_상태변화없는_sync는_발화하지_않는다() async {
        await startTracking()
        coach.sync()
        coach.sync()
        XCTAssertTrue(announcer.announced.isEmpty)
    }

    func test_종료하면_러닝종료_발화() async {
        await startTracking()
        session.finish()
        coach.sync()
        XCTAssertEqual(announcer.announced.count, 1)
        XCTAssertTrue(announcer.announced[0].hasPrefix("러닝 종료. 총 "))
    }

    func test_새러닝을_시작하면_km카운터가_리셋된다() async {
        await startTracking()
        let start = Date()
        stream.yield(sample(at: start.addingTimeInterval(300), metersNorth: 1005))
        await waitUntil { session.track.totalDistanceMeters > 1000 }
        coach.sync()
        session.finish()
        coach.sync()
        session.dismissSummary()
        coach.sync()
        announcer.announced.removeAll()

        // 두 번째 러닝: 다시 1km를 넘으면 "1킬로미터"가 다시 나와야 한다
        await startTracking()
        let restart = Date()
        stream.yield(sample(at: restart.addingTimeInterval(300), metersNorth: 1005))
        await waitUntil { session.track.totalDistanceMeters > 1000 }
        coach.sync()
        XCTAssertEqual(announcer.announced.count, 1)
        XCTAssertTrue(announcer.announced[0].hasPrefix("1킬로미터"))
    }

    func test_종료후_최종활동시간이_고정된다() async {
        await startTracking()
        XCTAssertNil(session.summaryActiveElapsedSeconds)
        session.finish()
        let first = session.summaryActiveElapsedSeconds
        XCTAssertNotNil(first)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(session.summaryActiveElapsedSeconds, first) // now가 지나도 안 자란다
    }
}

@MainActor
final class FakeVoiceAnnouncer: VoiceAnnouncerProtocol {
    var announced: [String] = []
    func announce(_ text: String) { announced.append(text) }
}
```

- [ ] **Step 3: 실패 확인**

Run:

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO \
  -only-testing:TraceTests/RunAudioCoachTests test
```

Expected: 컴파일 실패 — "cannot find 'RunAudioCoach' in scope"

- [ ] **Step 4: 최소 구현**

`Trace/Application/RunTracking/RunAudioCoach.swift` 생성:

```swift
import Foundation
import Observation

/// RunSession의 비뷰 소비자 — withObservationTracking으로 세션을 구독해 상태 전환·km 경계에서
/// 발화 문장을 조립해 VoiceAnnouncer에 넘긴다(스펙 §3.3). 세션 자체는 오디오를 모른다.
/// 구독·재등록 패턴은 RunActivityController와 동일.
@MainActor
final class RunAudioCoach {
    private let session: RunSession
    private let announcer: VoiceAnnouncerProtocol
    private var lastState: RunSession.State = .idle
    private var lastAnnouncedKm = 0

    init(session: RunSession, announcer: VoiceAnnouncerProtocol) {
        self.session = session
        self.announcer = announcer
    }

    func startObserving() {
        observeOnce()
    }

    private func observeOnce() {
        withObservationTracking {
            _ = session.state
            _ = session.track.totalDistanceMeters
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.sync()
                self.observeOnce() // 관찰은 1회성이라 재등록
            }
        }
    }

    /// 관찰 콜백의 유일한 진입점 — 테스트가 직접 호출해 발화 결정을 검증한다.
    func sync() {
        announceStateTransitionIfNeeded()
        announceKilometerIfNeeded()
        lastState = session.state
    }

    private func announceStateTransitionIfNeeded() {
        let state = session.state
        guard state != lastState else { return }
        switch (lastState, state) {
        case (.idle, .acquiring):
            lastAnnouncedKm = 0 // 새 러닝 — km 카운터 리셋
            announcer.announce(RunAnnouncementBuilder.start)
        case (.tracking, .paused):
            announcer.announce(RunAnnouncementBuilder.pause)
        case (.paused, .tracking):
            announcer.announce(RunAnnouncementBuilder.resume)
        case (_, .summary):
            let elapsed = session.summaryActiveElapsedSeconds ?? 0
            announcer.announce(RunAnnouncementBuilder.finish(
                distanceMeters: session.track.totalDistanceMeters,
                totalSeconds: elapsed,
                averagePaceSecondsPerKm: averagePace(elapsed: elapsed)
            ))
        default:
            break // acquiring→tracking(첫 샘플), 취소/권한회수로 인한 →idle 등은 발화 없음
        }
    }

    private func announceKilometerIfNeeded() {
        guard session.state == .tracking else { return }
        let km = Int(session.track.totalDistanceMeters / RunSplitCalculator.splitDistanceMeters)
        guard km > lastAnnouncedKm else { return }
        // 한 번에 여러 경계를 지난 극단 케이스는 최신 경계만 읽는다(밀린 발화 연쇄 방지)
        lastAnnouncedKm = km
        let elapsed = session.activeElapsedSeconds() ?? 0
        announcer.announce(RunAnnouncementBuilder.kilometer(
            km: km,
            totalSeconds: elapsed,
            averagePaceSecondsPerKm: averagePace(elapsed: elapsed)
        ))
    }

    /// 평균 페이스 = 활동 시간 / 거리 — 요약 화면(summaryAveragePaceSecondsPerKm)과 같은 기준(MVP14 §3.1)
    private func averagePace(elapsed: TimeInterval) -> Double? {
        let distance = session.track.totalDistanceMeters
        guard distance > 0, elapsed > 0 else { return nil }
        return elapsed / (distance / 1000)
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: Step 3과 동일 명령.
Expected: `Test Suite 'RunAudioCoachTests' passed` — 7개 테스트 전부 PASS.

- [ ] **Step 6: 기존 전체 테스트 회귀 확인 + 린트**

Run:

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO test
swiftlint
```

Expected: 전체 스위트 PASS(RunSession 변경은 additive 프로퍼티 1개), 린트 0.

- [ ] **Step 7: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 러닝 오디오 코치 — 상태 전환·km 경계 발화

- RunAudioCoach가 RunSession을 구독해 시작/일시정지/재개/종료와 km 경계에서 발화한다
- km 발화는 거리+총시간+평균 페이스, 전부 활동 시간 기준이다
- RunSession에 종료 시각으로 고정된 summaryActiveElapsedSeconds를 추가한다
- 발화 결정 로직은 페이크 어나운서로 단위 테스트한다" \
  -- Trace/Application/RunTracking/RunAudioCoach.swift Trace/Application/RunTracking/RunSession.swift \
     TraceTests/RunAudioCoachTests.swift
```

---

### Task 6: 배선 — DependencyContainer/TraceApp + 스파이크 버튼 제거

**전제: Task 1의 실기기 스파이크 통과 보고를 받은 뒤 진행한다.**

**Files:**
- Modify: `Trace/App/DependencyContainer.swift`
- Modify: `Trace/App/TraceApp.swift`
- Modify: `Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift` (스파이크 버튼 제거)

**Interfaces:**
- Consumes: `RunAudioCoach`(Task 5), `SpeechVoiceAnnouncer`(Task 1)
- Produces: `DependencyContainer.runAudioCoach: RunAudioCoach`

- [ ] **Step 1: DependencyContainer에 코치 추가**

`Trace/App/DependencyContainer.swift` 수정 — 프로퍼티 추가:

```swift
    let runAudioCoach: RunAudioCoach
```

`live()`에서 `runSession` 생성 아래에 코치를 만들고 반환에 포함:

```swift
        let runSession = RunSession(locationStream: RunLocationTracker(), recordRepository: runRecordRepository)
        let runAudioCoach = RunAudioCoach(session: runSession, announcer: SpeechVoiceAnnouncer())
```

(반환하는 `DependencyContainer(...)`에 `runAudioCoach: runAudioCoach` 인자 추가 — `uiTesting()`도 동일하게:)

```swift
        let runSession = RunSession(locationStream: UITestingRunLocationStream(), recordRepository: runRecordRepository)
        let runAudioCoach = RunAudioCoach(session: runSession, announcer: NoopVoiceAnnouncer())
```

파일 하단의 private UITesting 서비스들 옆에 무음 어나운서 추가(UI 테스트가 TTS 소리를 내지 않도록):

```swift
@MainActor
private final class NoopVoiceAnnouncer: VoiceAnnouncerProtocol {
    func announce(_ text: String) {}
}
```

- [ ] **Step 2: TraceApp에서 관찰 시작**

`Trace/App/TraceApp.swift`의 `init()`에서 기존 `startObserving` 아래에 추가:

```swift
        container.runActivityController.startObserving()
        container.runAudioCoach.startObserving()
```

- [ ] **Step 3: 스파이크 버튼 제거**

`Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift`에서 Task 1 Step 4로 넣었던
`#if DEBUG` 블록 2개(프로퍼티 `spikeAnnouncer`, 버튼)를 삭제한다. 이제 실제 발화 경로는
코치가 전담한다.

- [ ] **Step 4: 빌드 + 전체 테스트 + 린트 + 시뮬레이터 육안 확인**

Run:

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO test
swiftlint
```

Expected: 전부 PASS, 린트 0. 육안(청각) 확인: 시뮬레이터(소리 켬)에서 러닝 시작 →
"러닝 시작" 발화, 일시정지/재개 → 발화, City Run으로 1km 넘기면 → "1킬로미터…" 발화,
종료 → "러닝 종료…" 발화.

- [ ] **Step 5: 커밋**

```bash
scripts/trace-commit.sh -m "feat: 오디오 코치 배선 — 앱 전역에서 러닝 발화 활성화

- DependencyContainer가 RunAudioCoach를 생성하고 TraceApp이 관찰을 시작한다
- UI 테스트 컨테이너는 무음 NoopVoiceAnnouncer를 주입한다
- 스파이크용 DEBUG 발화 버튼을 제거한다(실경로는 코치 전담)" \
  -- Trace/App/DependencyContainer.swift Trace/App/TraceApp.swift \
     Trace/Pages/RunPage/UIComponent/RunPage+StatsPanelComponent.swift
```

---

### Task 7: 최종 검증 + 실기기 QA 체크리스트 + 코드리뷰

- [ ] **Step 1: 전체 스위트 + 린트 최종 실행**

Run:

```bash
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -parallel-testing-enabled NO test
swiftlint
```

Expected: 전체 PASS(기존 228개 + 신규 ~21개), 린트 위반 0. 통과 후 스탬프 갱신.

- [ ] **Step 2: 실기기 QA 체크리스트 작성**

`docs/qa/2026-07-XX-run-splits-audio-device-checklist.md` 작성(날짜는 작성일).
`docs/agent-rules/testing.md`의 시나리오 카드 템플릿을 따르고, **처음 쓰는 유저 기준 평이한
언어**(내부 용어 금지)로 쓴다. 반드시 포함할 시나리오:

1. **주머니 러닝(핵심)**: 음악 재생 + 화면 잠금 + 주머니 → 1km 지날 때 음악이 살짝 작아지며
   "1킬로미터. 총 시간 …" 안내가 나오고 음악 볼륨이 돌아오는가
2. 시작/일시정지/재개/종료 각각에서 안내 음성이 나오는가 (일시정지·재개는 화면 잠금 상태가 아닌
   앱에서 버튼을 누른 직후 — 진입점은 앱 버튼뿐)
3. 음악 없이도 안내가 나오는가 (무음 모드 스위치 상태에서도 — `.playback`은 무음 스위치 무시)
4. 방금 뛴 기록 상세에 "킬로미터별 페이스" 표가 나오는가 (일시정지를 낀 러닝이면 그 km의
   페이스가 멈춘 시간을 빼고 계산돼 있는가)
5. **과거 기록 소급**: 이번 업데이트 전에 저장해 둔 기록의 상세에도 표가 나오는가
6. 연속 발화(재개 직후 곧 km 경계 등)에서 음악 볼륨이 중간에 튀지 않고 발화가 순서대로 나오는가
7. **(밀린 확인, MVP13 이월)** 강제종료 후 재실행하면 잠금화면의 러닝 카드가 사라지는가
8. **(밀린 확인, MVP13 이월)** 20분+ 러닝에서 배터리 체감 확인
9. **(밀린 확인, MVP13 이월)** 건물 밀집지 GPS 정확도 (기회가 되면)

- [ ] **Step 3: 체크리스트 커밋**

```bash
scripts/trace-commit.sh -m "docs: run-splits-audio 실기기 QA 체크리스트 작성

- 주머니 시나리오(음악+잠금+km 발화 덕킹) 중심으로 구성한다
- 스플릿 표(신규+과거 기록 소급) 확인 항목을 포함한다
- MVP13에서 이월된 확인 3건을 다시 싣는다" \
  -- docs/qa/2026-07-XX-run-splits-audio-device-checklist.md
```

- [ ] **Step 4: 커밋 전 코드리뷰 요청 (superpowers:requesting-code-review)**

리뷰 통과 후 마무리. 실기기 QA는 사용자 수행 — 통과 보고를 받으면 `docs/roadmap.md`의
`run-splits-audio`를 `[x]`로 갱신하고, 통합(rebase + `--ff-only`)은 사용자 지시 시
`scripts/trace-integrate.sh`로.

---

## Self-Review 결과 (플랜 작성 시 수행)

- **스펙 커버리지**: §3.2 엔진(Task 2)·라이브/소급 공용(설계 노트+Task 3)·상세 표(Task 3) ✓,
  §3.3 포트/어댑터(Task 1)·세션 수명주기/덕킹/큐소진 복원(Task 1)·Background Mode audio(Task 1)·
  발화 큐 직렬화(AVSpeechSynthesizer 자체 큐, Task 1)·코치/문구(Task 4·5) ✓, §4 스키마 변경
  없음(스플릿 미저장) ✓, §5 스파이크 선행(Task 1)·단위 테스트 목록·주머니 QA·밀린 확인 3건(Task 7) ✓.
  목표 발화(§3.4)는 사이클 3 — 범위 밖 ✓.
- **이연 결정**: 오디오 세션 활성화 실패 → 스킵으로 종결(문서 상단 + project-decisions.md).
- **타입 정합**: `VoiceAnnouncerProtocol.announce(_:)`(T1)를 코치(T5)·페이크(T5)·Noop(T6)이 동일
  시그니처로 구현, `RunSplitCalculator.splits(samples:pauses:)`(T2)를 표(T3)가, `splitDistanceMeters`(T2)를
  코치(T5)가 사용, `summaryActiveElapsedSeconds`(T5 Step 1)를 코치(T5 Step 4)가 사용 — 일치 확인.
