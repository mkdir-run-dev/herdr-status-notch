# Herdr Status Notch

herdr 세션의 스페이스별 병목 상태를 맥 메뉴바와 노치 아래 패널로 보여 주는
macOS 앱이다. 목적은 "에이전트가 병목에 빠지지 않기"다. 0.7초 간격으로
`herdr api snapshot`을 폴링해 워크스페이스 칩을 메뉴바에 띄우고, 행을 클릭하면
`herdr agent focus <name>` / `herdr workspace focus <id>`로 포커스를 옮긴다.

## 메뉴바 구성

- **앱 아이콘**(MenuBarExtra). 그리드 아이콘 + 대기(idle) 인원수 뱃지.
  0명이면 숫자가 없고, herdr가 오프라인이면 아이콘이 빨간색이다.
- **스페이스 칩**(NSStatusItem). 신호(blocked·working·done·unknown)가 있는
  워크스페이스만 캡슐 칩으로 뜬다. 칩 안에는 상태 점들과 워크스페이스 라벨이
  들어가고 idle뿐인 잠든 스페이스는 숨겨진다. 정렬은 심각도
  (blocked → working → done → unknown)순, 동률은 워크스페이스 번호순이며
  상한 8개, 초과분은 드롭다운에 "+N more"로 표시된다. 칩을 클릭하면 소속
  에이전트 전원(idle 포함)과 "스페이스 포커스" 메뉴가 뜬다.

## 상태 색

macOS 시맨틱 색을 그대로 쓴다(브랜드 색 아님). 칩에는 idle 점이 없다.

| 상태 | 색 |
| --- | --- |
| working | 파랑 |
| done | 초록 |
| blocked | 호박(주황) |
| unknown(모르는 값 폴백) | 회색 |
| idle | 흰색(노치 패널 행 전용) |
| herdr 오프라인 | 빨강 |

## 앱 아이콘 드롭다운

1. herdr 오프라인이면 첫 행에 빨간 경고.
2. "대기 중 에이전트 N" 섹션. idle 에이전트의 이름 · 프로젝트(cwd 마지막
   컴포넌트) · 터미널 제목. 클릭하면 그 에이전트로 포커스.
3. 전체 스페이스 목록(잠든 스페이스 포함, 숨겨진 스페이스는 흐리게).
   클릭하면 그 스페이스로 포커스. 칩 상한 초과분은 "+N more".
4. 노치 패널 토글과 종료.

## 노치 패널

전체 에이전트(idle 포함)를 심각도순으로 나열한다. 토글(`UserDefaults`의
`notchPanelEnabled`, 기본 켜짐)로 표시를 끄면 패널을 만들지도 않는다.
패널의 빈 영역을 드래그해 옮길 수 있고 위치는 `UserDefaults`의
`notchPanelOrigin`에 저장돼 다음 실행에 복원된다.

## 요구 사항

- macOS 14.0 이상
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Xcode 명령줄 도구(`xcodebuild`)
- herdr CLI가 설치되어 있을 것. 앱은 PATH를 순회한 뒤
  `~/.local/bin/herdr`를 폴백으로 찾는다.

## 실행법

```bash
cd herdr-status-notch
xcodegen generate
xcodebuild -project HerdrStatusNotch.xcodeproj -scheme HerdrStatusNotch -configuration Debug build
```

또는 `xcodegen generate` 후 `HerdrStatusNotch.xcodeproj`를 Xcode에서 열어 실행한다.
`.xcodeproj`는 XcodeGen 산출물이라 저장소에 넣지 않는다(`.gitignore` 참조).

실행하면 메뉴바에 앱 아이콘과 스페이스 칩이 생기고, 노치 패널 토글이 켜져
있으면 화면 상단 중앙에 패널이 뜬다. Dock 아이콘은 숨겨진다(LSUIElement).

## 권한 안내

- `herdr agent focus`가 터미널 창 전환에 AppleScript/System Events를 쓰면
  macOS가 접근성 권한을 요구할 수 있다. 시스템 설정 → 개인 정보 보호 및
  보안 → 접근성에서 이 앱을 허용한다.
- 폴링은 읽기 전용 `herdr api snapshot`만 실행하므로 별도 권한이 필요 없다.

## 현재 한계

- 상태 갱신은 폴링(0.7초) 전용이다. 이벤트 스트림이나 웹소켓 구독이 없다.
- 노치 실측 좌표 기반 배치가 없다(저장 위치가 없으면 상단 중앙 고정).
- focus 명령의 성공/실패 피드백이 없다.

## 구조

- `Sources/App` — 앱 진입(MenuBarExtra)과 NSPanel·NSStatusItem 생명주기 담당 AppDelegate
- `Sources/Herdr` — herdr CLI 클라이언트, 데이터 모델(AgentSlot·WorkspaceInfo·SpaceChip·AgentStatus), 폴링 저장소
- `Sources/ChipBar` — 메뉴바 스페이스 칩(NSStatusItem diff 관리)과 스페이스 메뉴
- `Sources/NotchPanel` — 드래그 가능한 NSPanel과 배치 컨트롤러
- `Sources/Views` — 노치 패널 뷰, 앱 아이콘 드롭다운 뷰
