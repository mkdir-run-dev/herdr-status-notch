# Herdr Status Notch

herdr 세션 에이전트들의 상태를 맥 노치 아래 플로팅 패널과 메뉴바 위젯으로 보여 주는
macOS 앱 스캐폴드(MVP). 0.7초 간격으로 `herdr agent list` 결과를 폴링해 최대 8개
슬롯을 상태별 색 점과 함께 표시하고, 행을 탭하면 `herdr agent focus <name>`으로
해당 에이전트 터미널로 포커스를 옮긴다.

## 상태 색

macOS 시맨틱 색을 그대로 쓴다(브랜드 색 아님).

| 상태 | 색 |
| --- | --- |
| idle | 흰색 |
| working | 파랑 |
| done | 초록 |
| blocked | 호박(주황) |
| unknown(모르는 값 폴백) | 회색 |
| herdr 오프라인 | 빨강 |

슬롯 정렬은 blocked → working → done → idle → unknown 순서(같은 순위면 이름순)다.
9번째부터는 개수만 "N more" 행으로 메뉴바에 표시한다.

## 요구 사항

- macOS 14.0 이상
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Xcode 명령줄 도구(`xcodebuild`)
- herdr CLI가 설치되어 있고 세션 에이전트가 실행 중일 것.
  앱은 PATH를 순회한 뒤 `~/.local/bin/herdr`를 폴백으로 찾는다.

## 실행법

```bash
cd herdr-status-notch
xcodegen generate
xcodebuild -project HerdrStatusNotch.xcodeproj -scheme HerdrStatusNotch -configuration Debug build
```

또는 `xcodegen generate` 후 `HerdrStatusNotch.xcodeproj`를 Xcode에서 열어 실행한다.
`.xcodeproj`는 XcodeGen 산출물이라 저장소에 넣지 않는다(`.gitignore` 참조).

실행하면 메뉴바에 아이콘이 생기고, 세션 에이전트가 하나라도 있으면 화면 상단
중앙에 슬롯 패널이 뜬다. Dock 아이콘은 숨겨진다(LSUIElement).

## 권한 안내

- `herdr agent focus`가 터미널 창 전환에 AppleScript/System Events를 쓰면 macOS가
  접근성 권한을 요구할 수 있다. 시스템 설정 → 개인 정보 보호 및 보안 → 접근성에서
  이 앱을 허용한다.
- 폴링은 읽기 전용 `herdr agent list`만 실행하므로 별도 권한이 필요 없다.

## 노치 배치 안내

현재 패널은 보이는 화면 기준 상단 중앙에 고정된다. 실제 노치 좌표
(`NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`) 계산은 아직
구현되지 않았다(코드의 TODO 참조). 노치가 없는 맥에서는 메뉴바 바로 아래에 뜬다.

## 현재 한계

- 상태 갱신은 폴링(0.7초) 전용이다. 이벤트 스트림이나 웹소켓 구독이 없다.
- 노치 실측 좌표 기반 배치가 없다(상단 중앙 고정).
- 슬롯 8개 상한. 초과분은 개수만 표시된다.
- herdr가 오프라인이면 마지막 상태를 버리고 메뉴바에 빨간 행만 표시한다.
- focus 명령의 성공/실패 피드백이 없다.

## 구조

- `Sources/App` — 앱 진입(MenuBarExtra)과 NSPanel 생명주기 담당 AppDelegate
- `Sources/Herdr` — herdr CLI 클라이언트, 데이터 모델(AgentSlot·AgentStatus), 폴링 저장소
- `Sources/NotchPanel` — NSPanel 서브클래스와 배치 컨트롤러
- `Sources/Views` — 노치 패널 뷰, 메뉴바 위젯 뷰
