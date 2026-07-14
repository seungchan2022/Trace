---
title: "INFOPLIST_KEY_* 빌드 설정은 배열/딕셔너리 값을 합성하지 못한다"
date: 2026-07-13
category: build-errors
module: Trace.xcodeproj (Info.plist 생성)
problem_type: build_error
component: tooling
symptoms:
  - "project.pbxproj의 빌드 설정에 `INFOPLIST_KEY_UIBackgroundModes = location;`을 추가했지만, 빌드된 앱의 Info.plist에는 `UIBackgroundModes` 키 자체가 나타나지 않음(조용히 누락, 빌드 에러 없음)"
  - "임의의 다른 배열/딕셔너리 타입 Info.plist 키(`NSLocationTemporaryUsageDescriptionDictionary` 등)도 동일하게 `INFOPLIST_KEY_*` 형태로는 반영되지 않음"
root_cause: config_error
resolution_type: config_change
severity: medium
tags: [xcode, infoplist, generate-infoplist-file, build-settings, ios]
---

# INFOPLIST_KEY_* 빌드 설정은 배열/딕셔너리 값을 합성하지 못한다

## Problem

`GENERATE_INFOPLIST_FILE = YES`인 프로젝트에서 `INFOPLIST_KEY_<Key>` 빌드 설정으로 Info.plist 키를 지정하는 방식은 스칼라(문자열/불리언 등) 값에는 동작하지만, 배열이나 딕셔너리 타입 값을 요구하는 키(`UIBackgroundModes`, `NSLocationTemporaryUsageDescriptionDictionary` 등)에는 조용히 무시된다 — 빌드는 성공하고 에러도 없이, 그냥 빌드된 앱의 Info.plist에 해당 키가 빠진다.

## Symptoms

- MVP13 run-tracking Task 3에서 백그라운드 위치 추적을 위해 `Trace.xcodeproj/project.pbxproj`에 `INFOPLIST_KEY_UIBackgroundModes = location;`을 앱 타깃 Debug/Release 블록에 추가했다.
- 빌드는 정상적으로 성공했지만, `plutil -p .../Trace.app/Info.plist`로 확인한 결과 `UIBackgroundModes` 키가 아예 존재하지 않았다.
- 임의의 커스텀 키로 통제 실험(control test)을 해봐도 같은 현상 — `INFOPLIST_KEY_*` 메커니즘 자체가 배열/딕셔너리를 합성하지 못하는 것으로 확인됐다(스칼라 값은 정상 동작 — 같은 커밋에서 `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`은 문자열이라 정상 반영됨).

## What Didn't Work

- 브리프에 적힌 대로 `INFOPLIST_KEY_UIBackgroundModes = location;`을 그대로 추가 — 빌드는 성공하지만 실제 Info.plist에 반영되지 않아, 런타임에 `CLLocationManager.allowsBackgroundLocationUpdates = true`를 호출하면 Background Modes capability 부재로 크래시(`NSInvalidArgumentException`)했을 것(이번엔 사전에 발견해 실제 크래시로 이어지지 않음).

## Solution

배열/딕셔너리 타입 Info.plist 키는 `INFOPLIST_KEY_*` 빌드 설정 대신, `INFOPLIST_FILE` 빌드 설정으로 지정한 보조 plist 파일(`GENERATE_INFOPLIST_FILE = YES`와 병존 가능 — Xcode가 파일과 생성 키를 병합한다)에 리터럴로 선언한다:

`Config/Trace-Info.plist`:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
</array>
<key>NSLocationTemporaryUsageDescriptionDictionary</key>
<dict>
    <key>RunTracking</key>
    <string>...</string>
</dict>
```

`project.pbxproj`(앱 타깃 Debug/Release 두 블록 모두):
```
INFOPLIST_FILE = "Config/Trace-Info.plist";
GENERATE_INFOPLIST_FILE = YES;  // 유지 — 병합됨
INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "...";  // 스칼라는 이 방식 그대로 유지
```

## Why This Works

`INFOPLIST_KEY_<Key>` 빌드 설정은 Xcode의 Info.plist 자동 생성기가 문자열/불리언 등 단일 스칼라 값을 합성하는 경로만 지원한다. 배열이나 딕셔너리가 필요한 키는 이 경로로 표현할 방법이 없어(문법상 막는 게 아니라 조용히 드롭됨), `INFOPLIST_FILE`로 지정한 실제 plist 파일에 직접 써야 한다. `GENERATE_INFOPLIST_FILE = YES`를 유지하면 Xcode가 이 파일과 나머지 `INFOPLIST_KEY_*` 스칼라들을 병합해 최종 Info.plist를 만든다 — 스칼라는 빌드 설정으로, 배열/딕셔너리는 파일로 나눠 쓰는 게 이 프로젝트의 방식이다.

## Prevention

- 새 Info.plist 키를 추가할 때, 그 키의 plist 값 타입이 배열이나 딕셔너리이면 처음부터 `INFOPLIST_KEY_*` 빌드 설정을 시도하지 말고 `INFOPLIST_FILE`로 지정한 보조 plist 파일에 직접 쓴다.
- `INFOPLIST_KEY_*`로 배열/딕셔너리 키를 추가한 뒤에는 반드시 빌드된 앱의 실제 Info.plist를 `plutil -p`로 확인한다 — 빌드 성공 여부만으로는 이 누락을 잡을 수 없다.
- 이 프로젝트에서 background modes·temporary usage description 등 배열/딕셔너리 키가 필요하면 `Config/Trace-Info.plist`에 함께 추가한다.

## Related Issues

- 구현: `Trace/Infrastructure/Location/CoreLocation/RunLocationTracker.swift`, `Config/Trace-Info.plist`, `Trace.xcodeproj/project.pbxproj`(앱 타깃 Debug/Release 두 블록)
- 플랜: `docs/superpowers/plans/2026-07-13-run-tracking.md` (Task 3) — 브리프 원안은 `INFOPLIST_KEY_UIBackgroundModes`를 지정했으나 구현 중 이 한계를 발견해 조정함
