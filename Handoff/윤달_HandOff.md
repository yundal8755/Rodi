# 윤달 HandOff

## Current

- 브랜치: `release/1.4.1`
- 작업 상태: Presentation 리팩터링 진행 중

## Recent Work

- `release/1.4.1`에서 배포 설정·Live Activity target 분리·로컬 저장소 공통화·Kakao 지도 transport·코스 등록·Home·Login/Onboarding·My/Review/PracticeTracking을 책임 단위로 분리 커밋했다. 최종 빌드 및 push 확인이 남아 있다.
- Fastlane 추적 파일에서 숫자형 App Store ID와 팀 ID를 제거하고, 로컬 `fastlane/.env` 또는 CI 환경 변수·local secrets로만 제공하도록 정리했다. bundle identifier는 앱 번들에 포함되는 공개 식별자로 유지한다.
- 1.4.1 App Store 패치노트를 배포 전 초안으로 추가했다.
- 코스 등록에서 초기 출발지 후보 주소를 확인하는 동안에도 출발지 입력 행으로 장소 검색에 진입할 수 있게 했고, 도로 경로 조회 실패 뒤 마지막 선택 지점의 중앙 핀을 유지하도록 보완했다.
- 코스 등록의 경유지 삭제 버튼을 선택 진행 상태와 분리하고, 지도 중심 주소는 새 reverse-geocoding 결과가 도착할 때까지 이전 값을 유지하도록 보완했다.
- My 프로필의 도장·게이지 레이어 순서와 면허증 카드 방사형 그라데이션을 정리하고, 운전 목표의 기존 값 전달·자동 포커스를 보완했다.
- 설정에 데이터 출처 SubPage를 추가하고, 연습기록 3개 후기 상태와 내 활동 드롭다운 drag 종료를 공용 Component·View-local interaction으로 정리했다.
- 주차장 후기 권유 팝업의 X도 방문 기록 처리로 연결했다. `안 했어요`는 기존처럼 기록하지 않는다.

- 코스 등록 튜토리얼을 드래그 pager와 상단 완료 아이콘으로 전환하고, 지도 중심 후보 주소·출발지/도착지 확정 흐름 및 행정구역 검색 이동을 정리했다. 수동 UI 확인이 남아 있다.
- Login의 Apple/Kakao SDK continuation·timeout을 Adapter로 이동하고, 코스 등록·장소 검색·길찾기의 Kakao REST transport를 공통 client로 정리했다.
- Home Search·Course Review·Home root의 표시 State를 Model로 분리하고, BottomSheet chrome/drag handle을 Component로 분리했다.
- Root→MainTab 입력을 `MainTabPresentation`으로 묶어 다수 callback·request ID 전달을 줄였다.
- 코스·주차장 길안내의 외부 앱 실행·측정 준비·설정 복귀를 BottomSheet reducer와 `RouteGuidanceFlowService`로 이동해 View의 직접 singleton·`Task` 호출을 제거했다.
- My 로그아웃의 Kakao SDK callback을 Login Feature의 `SocialSessionService`로 이동했다.
- Presentation 리팩터링 백로그를 미완료 P0·P1·P2와 완료 항목 표로 분리했다.
- Debug 폴더를 제외한 Presentation 전체를 정적 감사해 8개 Feature의 활성 후보, 보류 항목, 현 구조 유지 항목을 백로그에 확정했다.
- CourseRegistration root View를 route 조립 중심으로 축소했다.
- 지도 선택·핀 수정 View와 공통 Component를 책임 위치로 분리했다.
- 장소 검색 State를 부모 reducer가 소유하도록 전환하고, snackbar·비동기 요청의 취소 및 stale-result 방어를 reducer Effect로 정리했다.
- HandOff 운영 규칙을 도입하고, 중복된 루트 TODO를 `Docs/TODO`로 이관해 문서 원본을 단일화했다.
- Live Activity Widget UI·공유 `ActivityAttributes`·app-only runtime service를 `RodiPracticeLiveActivity/` 아래로 이동하고, app/extension target membership을 명시적으로 분리했다.
- My Feature가 `AppDependencies` 전체 대신 `MyFeatureDependencies`만 받도록 조립 경계를 축소했다.
- Home·Onboarding도 각각 Feature dependency 입력 모델을 사용하도록 바꿔 App 조립 객체의 Presentation 전파를 줄였다.
- `RouteGuidanceFlowService`의 main-actor default argument 경고와 Home heading stream의 불필요한 `await`를 제거했다.
- My Posts 화면 생성에 필요한 repository를 `MyPostsFeatureDependencies`로 묶어 상위 View의 조립 책임을 줄였다.
- Onboarding의 법적 설정 화면을 Component 밖의 독립 SubPage로 이동했다.
- 취소된 Home 지도 좌표 조회가 실패 UI로 전환되지 않도록 `MapService`의 cancellation 판별을 수정했다.
- MainTab도 `MainTabFeatureDependencies`를 통해 필요한 Feature 의존성만 전달하도록 정리했다.
- My Posts·코스 후기 dropdown 및 코스 등록 튜토리얼의 `GeometryReader`는 iOS 16.1에서 실제 anchor/컨테이너 비율 측정 책임이 있음을 확인해 유지로 확정했다.
- Presentation 일반 Feature의 모호한 TODO/FIXME를 제거하고, 후속 책임은 리팩터링 백로그에 단일화했다.
- My 설정 화면을 account, information, permission SubPage로 분리하고, Presentation의 직접 `UserDefaults` 접근을 `Data/Local/Support` persistence 표현으로 이동했다.
- 후기 완료 뒤 결과를 버리던 prefetch를 제거하고, PracticeTracking 인증 재시도 Task에 취소·최신성 검증을 추가했다.
- Home Search의 최근 검색과 결과 목록 state를 분리하고, CourseDetail 후기 dropdown·카드 메뉴의 표시/행동 해석을 Review Feature Component로 이동했다.
- BottomSheet의 순수 높이·opacity·settle 목적지 계산을 `HomeBottomSheetLayout`로 분리했다. 실제 pan 진행값·settlement task는 View-local로 유지했다.
- Onboarding의 guest/member별 복원 navigation path 정책을 `OnboardingNavigationPath` Model로 이동했다.
- My Posts의 후기·코스 목록을 각각 child reducer로 분리해 pagination·삭제·최신성 검증을 각 owner에 유지했다.
- MainTab→Home 입력을 `HomePresentation`으로 묶고, Home 길안내 dialog와 BottomSheet route 콘텐츠를 전용 Component로 분리했다.
- My root와 Onboarding은 재감사 결과 독립 destination/route host로서 현재 경계가 적절함을 확인해 P1 완료 항목으로 옮겼다.
- Home 상세 전환을 child reset 뒤에 처리하도록 바꾸고, 후기·코스 등록 종료 시 child Effect 취소 경로를 보완했다.
- Home의 검색·코스 확장·코스 후기 full-screen cover 조립을 `HomePresentationHost`로 이동했다.
- QA 이슈 로그를 고정 환경(iPhone 12 Pro / iOS 18.7.8)과 한 줄 TODO 기록 형식으로 정리했다.
- Home 지도 엔진 준비 전 누락될 수 있는 내 위치 마커 재동기화와 초기 렌더 뒤 재시도를 추가했다.
- Home 활성·권한 허용 상태에서 60초 단위로 위치 마커를 갱신하고, 주기 갱신이 카메라를 이동시키지 않게 했다.
- 온보딩 운전 경험에서 Q1 선택 직후 Q2·Q3을 함께 노출하도록 수정했다.
- Swift 6 기본 MainActor 격리에서 발생한 네트워크 오버레이 deinit, 서버 날짜 parser, 코스 등록 Kakao client 기본 인자, Debug 탈퇴 callback의 isolation·Sendable 진단을 정리했다.
- 홈 코스 마커 선택에만 확대 카메라 레벨을 적용하고, 최근 검색 내역·검색 결과 없음 empty state를 검색 화면에서 분리해 표시했다.
- 홈 검색 지역 후보는 `/api/v1/places/related-search` 응답 원문을 표시하며, `korean_administrative_areas.json`은 코스 등록 검색 전용임을 확인했다.
- 홈 검색의 최근·지역 결과 divider를 full-width로 정리하고, 검색 결과 없음 empty state를 중앙 정렬했다.
- 검색·마커 선택의 active marker와 검색창 선택 장소명을 동기화하고, 지역 검색 시 상세 teardown 뒤 추천 목록을 표시하도록 정리했다.
- 코스·주차장 하단 행동 바의 상단 divider·10pt 간격과 추천 목록·코스 상세 56pt 앱바를 적용했다.
- 코스 등록 튜토리얼 stepper는 드래그 중간값을 제거하고 page settle 시에만 4pt 단계로 갱신하도록 단순화했으며, 코스·추천 목록 collapsed 시 drag handle 아래 여백과 코스 확장 화면의 소개·경로 정보 간격을 조정했다.
- 전역 네트워크 화면 오버레이를 제거하고, 모든 화면에는 공통 네트워크 스낵바만 표시하도록 변경했다. Home 지도에서만 단절이 3초 지속될 때 지도 대체 화면을 표시한다.
- 코스 등록의 경유지·도착지 주소 preview는 placeholder를 비우고, 경유지를 추가하면 현재 중앙 핀 주소를 즉시 조회하며 출발지 확정 뒤 도착지에는 출발지 좌표의 주소를 바로 표시하도록 보완했다.
- 홈·코스 등록 검색의 debounce 및 다음 페이지 로딩 spinner를 실제 목록 밀도의 skeleton 행으로 교체했다.
- Home 위치 갱신은 마지막 성공 위치를 유지하고, 60초 이상 지난 주기 갱신 실패에서만 GPS 미수신 안내를 한 번 보이도록 보완했다. 성공 수신 시 안내 상태를 초기화한다.
- 경유지 추가 직후에는 이전 출발지 주소를 복사하지 않고 `경유지 입력`을 유지하며, 지도 이동 후 중앙 핀 주소로 바뀌게 수정했다.
- title 영역까지 넓힌 바텀시트 drag hit 영역은 기능 오류를 피하기 위해 기존 indicator 영역 방식으로 되돌렸다.

## Next

- iPhone 12 Pro에서 최초 출발지 선택 전 검색 진입과 도로 경로 조회 실패 뒤 중앙 핀 유지 상태를 수동 QA한다.
- 실제 Fastlane 배포 전에는 `fastlane/.env.example`을 참고해 로컬 또는 CI에 `FASTLANE_ITC_TEAM_ID`, `FASTLANE_TEAM_ID`를 제공하고, local secrets의 환경별 `APP_STORE_APP_ID`를 확인한다.
- iPhone 12 Pro에서 경유지 삭제·주소 유지, My 프로필/설정/연습기록/드롭다운, 주차장 팝업 X 후 연습기록 저장을 수동 QA한다.
- iPhone 12 Pro에서 코스 등록 튜토리얼 drag·상단 완료, 중앙 핀 주소 preview, 출발지/도착지 확정, 지역 검색 이동과 빈 결과 화면을 수동 QA한다.
- P1 Debug callback의 Release 계약 제거와 Home Map·길안내 child reducer 분리 후보를 별도 묶음으로 검토한다.
- QA 진행 중 `Docs/TODO/QA_ISSUES.md`의 TODO에 재현·기대·실제·증거를 기록하고, 확정 이슈부터 수정한다.
- P2 실기기 UI QA와 장문 파일 중 실제 독립 책임이 확인되는 항목만 후속으로 정리한다.
- 코스·주차장 길안내, Live Activity 설정 복귀, 로그아웃과 후기 완료·인증 재시도를 수동 QA한다.
- iPhone 12 Pro에서 신규 설치 후 위치 권한 허용, Home 60초 위치 갱신, 온보딩 Q1 이후 Q2·Q3 동시 노출을 수동 QA한다.
- iPhone 12 Pro에서 검색·지도 마커 선택, 상세 중 지역 검색 전환, 코스·주차장 행동 바와 56pt 앱바를 수동 QA한다.
- iPhone 12 Pro에서 튜토리얼 좌우 전환 완료·뒤로가기 stepper 동기화, collapsed 코스·추천 시트 상단 간격, 확장 코스 상세 소개·경로 정보 24pt 간격을 수동 QA한다.
- iPhone 12 Pro에서 검색 skeleton, 60초 GPS 미수신 단일 안내, 경유지 placeholder→중앙 핀 주소 전환, 기존 바텀시트 indicator drag를 수동 QA한다.
- Presentation 리팩터링 backlog의 My Posts pagination·삭제 flow, Onboarding route host, MainTab intent, Home child ownership 항목을 순서대로 진행한다.

## Validation

- Fastlane `ios version` lane 성공. Dev는 `1.0.0 (1)`, 로컬 Prod 설정은 `1.4.1 (0)`으로 확인됐다.
- Fastlane 식별자 분리·코스 등록 검색/경로 실패 상태 변경 뒤 `Rodi Dev` Debug build 성공. 수동 UI QA 대기.
- iPhone 17 Pro(iOS 26.2) simulator에 Dev 앱 설치·실행 성공. 로그인 화면까지 정상 표시됐으며, My·코스 등록·주차장 길안내 시나리오는 로그인 세션과 실제 서버 데이터가 필요해 수동 QA 대기.
- 남은 QA 수정 뒤 `Rodi Dev` Debug build 성공. 변경 범위 `git diff --check` 통과. 수동 QA 미실행.
- 코스 등록 튜토리얼·지도 선택·지역 검색 변경 뒤 `Rodi Dev` Debug build 성공. 수동 UI QA 미실행.
- Login adapter·Kakao REST transport·Home state/component·MainTab presentation 변경 뒤 `Rodi Dev` Debug build 성공
- `Rodi Dev` Debug build 성공
- `git diff --check` 통과
- Live Activity 구조 이동 후 `Rodi Dev` Debug build 성공
- 길안내 I/O·로그아웃 경계 정리 후 `Rodi Dev` Debug build 성공
- 이번 변경 범위의 `git diff --check` 통과 (`WithdrawalAccountDialog.swift`의 기존 trailing whitespace 제외)
- 수동 QA 미실행
- Debug 제외 Presentation 정적 감사 완료, 코드·UI·API 변경 없음
- My 의존성·설정 분리, Data/Local persistence 표현, 후기 refresh 제거, 인증 재시도 최신성 변경 뒤 `Rodi Dev` Debug build 성공
- Home·Onboarding dependency 입력 모델과 concurrency 경고 정리 뒤 `Rodi Dev` Debug build 성공
- My Posts dependency 입력 모델 정리 뒤 `Rodi Dev` Debug build 성공
- LegalSettings SubPage 이동과 지도 취소 처리 뒤 `Rodi Dev` Debug build 성공
- MainTab dependency 입력 모델 정리 뒤 `Rodi Dev` Debug build 성공
- GeometryReader 재판정과 TODO 정리 뒤 `Rodi Dev` Debug build 성공
- `git diff --check`는 기존 `WithdrawalAccountDialog.swift` trailing whitespace 1건으로만 실패
- Home Search state, CourseDetail Review dropdown ownership, BottomSheet layout policy 변경 뒤 `Rodi Dev` Debug build 성공
- Onboarding navigation path Model 분리 뒤 `Rodi Dev` Debug build 성공
- My Posts child reducer, Home presentation·길안내 overlay, BottomSheet route 콘텐츠 분리 뒤 `Rodi Dev` Debug build 성공
- Home child teardown과 presentation host 분리 뒤 `Rodi Dev` Debug build 성공
- QA 이슈 로그 문서 구조 확인 및 `git diff --check` 대기
- 내 위치 마커 재동기화·60초 갱신·온보딩 질문 노출 변경 뒤 `Rodi Dev` Debug build 성공
- Swift 6 isolation·Sendable 정리 뒤 `Rodi Dev` Debug 및 `Rodi` Release simulator build 성공
- 홈 지도·검색 QA 수정 뒤 `Rodi Dev` Debug build 성공
- 홈 검색·장소 선택·바텀시트 QA 수정 뒤 `Rodi Dev` Debug build 성공
- 이번 변경 파일 범위 `git diff --check` 통과. 전체 검사에는 기존 `WithdrawalAccountDialog.swift`, `MyDrivingGoalView.swift` trailing whitespace가 남아 있음.
- 튜토리얼 pager 동기화·stepper 4pt·코스/추천 목록 시트 간격 조정 뒤 `Rodi Dev` Debug build 성공. 수동 UI QA 대기.
- 튜토리얼 stepper의 드래그 중간 진행값 제거 뒤 `Rodi Dev` Debug build 성공. 수동 UI QA 대기.
- 네트워크 단절 표시·코스 등록 주소 preview·바텀시트 drag hit 영역 변경 뒤 `Rodi Dev` Debug build 성공. 수동 UI QA 대기.
- 검색 skeleton·GPS 미수신 단일 안내·경유지 placeholder·바텀시트 drag 복구 변경 뒤 빌드 및 수동 QA 대기.
