import AppIntents

/// 잠금화면 Live Activity 버튼 인텐트(스펙 §2.3) — LiveActivityIntent는 앱 프로세스에서
/// 실행되므로(필요 시 백그라운드 런치) 살아 있는 RunSession에 직접 연결된다(IPC 불필요).
/// perform은 앱 시작 시 등록되는 핸들러에 위임한다 — 이 파일은 위젯 타깃에도 컴파일되지만
/// (Button(intent:)가 타입을 알아야 함) 핸들러는 앱 프로세스에서만 등록된다.
struct MarkRunWaypointIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "포인트 찍기"
    /// 잠금화면 버튼 전용 — Shortcuts 앱 노출 불필요
    static let isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await MarkRunWaypointIntentBridge.performMark()
        return .result()
    }
}

/// 인텐트 → 앱 세션 연결 지점. TraceApp.init(인텐트로 인한 백그라운드 콜드 런치에서도
/// perform 전에 실행됨)에서 핸들러가 등록된다.
@MainActor
enum MarkRunWaypointIntentBridge {
    static var handler: (@MainActor () async -> Void)?

    static func performMark() async {
        await handler?()
    }
}
