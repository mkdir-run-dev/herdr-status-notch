# Herdr Status Notch

> Watch herdr coding-agent workspaces for bottlenecks from the macOS menu bar and a floating notch panel. Built to use Codex Micro in software.

herdr 에이전트가 입력이나 확인을 기다리며 멈춰 있지 않도록, 스페이스별 병목 상태를 macOS 메뉴바와 노치 아래 패널로 보여 주는 앱이다. Codex Micro 장비를 소프트웨어로 쓰고 싶어서 만들었고 상태 색 매핑도 그대로 따른다.

## 한눈에 보기

- **메뉴바 칩**: 주의가 필요한 스페이스만 캡슐 칩으로 띄운다(`blocked → done → working` 순). 클릭하면 해당 스페이스로 바로 포커스가 이동한다.
- **노치 패널**: 전체 스페이스와 탭별 작업명·모델을 한눈에 보여 준다. 스페이스 헤더 클릭 시 스페이스, 탭 행 클릭 시 탭으로 이동한다. 본문 드래그로 위치 이동, 좌우 가장자리 드래그로 폭 조절이 가능하다.
- **앱 아이콘 드롭다운**: 잠든 스페이스(전원 `idle`) 수 뱃지를 표시한다. 클릭하면 전체 스페이스 지도, 노치 패널 토글, 로그인 시 시작, 언어(시스템 따름·한국어·English), 종료 메뉴가 뜬다.
- **자동 포커스**: 칩·드롭다운·노치 패널 어디서든 클릭하면 Rex(herdr GUI)가 꺼져 있거나 창이 닫혀 있어도 먼저 띄워 앞으로 가져온 뒤 이동한다.

## 상태 색

macOS 시맨틱 색을 그대로 쓴다.

| 상태 | 색 | 의미 |
| --- | --- | --- |
| `blocked` | 주황(호박) | 입력 대기. 지금 확인 필요 |
| `done` | 초록 | **종료 · 확인 필요** (성공 보장이 아님) |
| `working` | 파랑 | 작업 중 |
| `idle` | 회색 | 대기 중 (메뉴바 칩 숨김, 노치 패널 탭 점 전용) |
| `unknown` | 회색 | 알 수 없는 상태값 폴백 |
| herdr 오프라인 | 빨강 | 연결 끊김 (앱 아이콘 + 드롭다운 경고) |

> [!IMPORTANT]
> **`done`(초록)은 "성공 완료"가 아니다.** herdr 상태 모델에 실패 값이 없어 정상 종료·에이전트 사망·강제 종료가 모두 `done`으로 온다. 초록이 뜨면 해당 에이전트를 직접 확인해야 한다. 확인해서 `idle`로 바뀌는 순간 칩이 즉시 사라지며 별도 타임아웃은 없다.

## 설치 및 실행

**요구 사항**: macOS 14.0 이상, `herdr` CLI (`PATH` 또는 `~/.local/bin/herdr`) + Rex (herdr GUI). 상태 표시는 herdr CLI만으로 동작하지만 칩·패널 클릭의 포커스 이동 대상은 Rex다.

### Release에서 설치
1. Release에서 `.zip`을 내려받아 압축을 푼다.
2. `HerdrStatusNotch.app`을 `/Applications/`로 옮긴다.
3. ad-hoc 서명 앱이라 첫 실행 시 게이트키퍼 경고가 뜬다. **우클릭 → 열기**로 한 번 허용하면 이후 더블클릭으로 실행된다.

### 소스에서 빌드
추가 필요 도구: [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), Xcode 명령줄 도구(`xcodebuild`)

```bash
cd herdr-status-notch
xcodegen generate
xcodebuild -project HerdrStatusNotch.xcodeproj -scheme HerdrStatusNotch -configuration Debug build
cp -R ~/Library/Developer/Xcode/DerivedData/HerdrStatusNotch-*/Build/Products/Debug/HerdrStatusNotch.app /Applications/
```

Xcode에서 직접 실행하려면 `xcodegen generate` 후 `HerdrStatusNotch.xcodeproj`를 열면 된다(`.xcodeproj`는 생성 산출물이라 저장소에 넣지 않는다).

## 권한 및 설정

- **접근성 권한**: 포커스 전환이 AppleScript/System Events를 쓸 때 macOS가 권한을 요구할 수 있다. `시스템 설정 → 개인 정보 보호 및 보안 → 접근성`에서 허용한다. 폴링은 읽기 전용이라 권한이 필요 없다.
- **로그인 시 시작**: 드롭다운에서 켠다(`SMAppService`). 앱이 `/Applications/`에 있어야 등록이 유지된다.
- **Dock 숨김**: 런타임에 accessory 모드로 전환해 Dock 아이콘은 숨기고 런치패드에만 노출한다.

---

<details>
<summary>상세 동작 규칙 (칩 정렬·제한, 노치 패널, 작업명 추출, 언어)</summary>

### 메뉴바 칩 규칙
- **표시·사라짐**: 신호(`blocked·working·done·unknown`)가 있는 스페이스만 칩(최악 상태 점 1개 + 라벨)으로 뜬다. 전원 `idle`인 잠든 스페이스는 즉시 숨겨진다.
- **정렬**: 기준은 심각도가 아니라 '사용자를 기다리는 정도'다(`blocked → done → working → unknown`, 동률은 워크스페이스 번호순). 상태가 바뀌면 자동으로 재배치되어 `blocked`가 가장 왼쪽에 온다.
- **표시 상한**: 최대 8개와 칩 폭 합계 예산(약 480pt) 중 먼저 차는 쪽에서 끊는다. 초과분은 드롭다운 스페이스 지도에서 본다. 긴 라벨은 최대폭(110pt)에서 `…`로 잘린다.
- **메뉴바 위치**: 전체 칩을 `NSStatusItem` 하나로 합성해 그리므로 다른 앱 아이콘이 칩 사이에 끼어들지 않는다. 첫 실행 시 왼쪽 끝에 배치되며 `⌘`-드래그로 위치를 옮길 수 있다.

### 노치 패널 규칙
- **계층**: 상단 "전체 스페이스(All spaces) N" 헤더 아래 스페이스별 섹션(대표 상태 점·스페이스명·에이전트 종류 요약)과 탭 행(상태 점·탭명·작업명·모델)이 붙는다. 잠든 스페이스는 섹션 전체를 흐리게 그린다.
- **토글·크기·위치**: 드롭다운 스위치(`notchPanelEnabled`, 기본 켜짐)로 끄면 패널을 만들지 않는다. 드래그 위치(`notchPanelOrigin`)와 좌우 리사이즈 폭(`notchPanelWidth`, 220~600pt, 기본 320pt)은 `UserDefaults`에 저장해 다음 실행에 복원한다.

### 작업명 추출 (3단계 폴백)
노치 패널 탭 행의 작업명은 아래 순서로 찾는다.
1. 에이전트 시작 시 심은 공식 메타데이터 (`herdr pane report-metadata <pane> --source <source> --token summary="..."`).
2. 터미널 제목에서 상태 글리프(`✳ ◑ ◐`)와 도구 이름(`Claude Code` 등)을 걸러낸 값.
3. 에이전트 `cwd`의 git 브랜치명 (`/usr/bin/git rev-parse --abbrev-ref HEAD`, 신호 탭 소속만 조회).

### 인터페이스 언어
드롭다운에서 `시스템 따름(기본)`·`한국어`·`English`를 고른다. 선택은 `UserDefaults(appLanguage)`에 저장되고 코드 표(`AppText`)로 화면을 다시 그려 재시작 없이 즉시 적용된다.

</details>

<details>
<summary>기술 상세 (성능, 보안, 현재 한계, 코드 구조)</summary>

### 성능 (실측)
- 0.7초 폴링 주기당 `herdr api snapshot` 1회 약 5ms, git 브랜치 조회는 서로 다른 `cwd`당 약 19ms(신호 탭 소속만, 같은 `cwd`는 1회)다.
- 백그라운드 큐에서 순차 실행하며 응답이 늦으면 다음 틱을 건너뛴다.
- 메뉴바 칩은 구성이나 상태가 바뀐 경우에만 다시 그린다.

### 보안
- 네트워크 송수신이 없다. 디스크 쓰기는 `UserDefaults` 설정 키(`notchPanelEnabled`, `notchPanelOrigin`, `notchPanelWidth`, `appLanguage`, 메뉴바 위치 키)뿐이다.
- 모든 외부 프로세스 실행은 인자 배열로 직접 전달한다(셸 없음). `herdr`는 `PATH` 순회 후 `~/.local/bin/herdr` 폴백, git은 `/usr/bin/git`, GUI 실행은 `/usr/bin/open`으로 경로를 고정한다.
- 외부 입력(`herdr` JSON)은 디코드 경계 한 곳에서만 파싱하며 가변 필드는 옵셔널로 읽는다.

### 현재 한계
- 상태 갱신은 0.7초 폴링 전용이다(이벤트 스트림·웹소켓 구독 없음).
- 노치 실측 좌표 기반 배치가 없다(저장 위치가 없으면 보이는 화면 상단 중앙 고정).
- focus 명령의 성공/실패 피드백이 없다.
- summary 토큰·터미널 제목·git 브랜치 어느 것도 없으면 작업명이 비어 있다.

### 코드 구조
- **Sources/App**: 앱 진입(`MenuBarExtra`), 패널·칩바 생명주기를 관리하는 `AppDelegate`, 로그인 시 시작(`LoginItemService`).
- **Sources/Herdr**: `herdr` CLI 클라이언트(`HerdrClient`), 데이터 모델(`AgentSlot`·`SpaceChip`·`AgentStatus`), 폴링 저장소(`SlotStore`), Rex 활성화(`RexLauncher`), 문구 표(`AppLocalization`).
- **Sources/ChipBar**: 단일 `NSStatusItem` 합성 칩 스트립(`ChipBarManager`)과 폭·잘림 계산(`ChipMetrics`).
- **Sources/NotchPanel**: 드래그 이동·좌우 폭 리사이즈 가능한 `NSPanel`과 상단 앵커 컨트롤러.
- **Sources/Views**: 노치 패널 뷰(`NotchPanelView`)와 앱 아이콘 드롭다운 뷰(`MenuBarRootView`).

</details>

## 라이선스

GNU GPL v3. 전문은 [LICENSE](LICENSE) 파일에 있다.
