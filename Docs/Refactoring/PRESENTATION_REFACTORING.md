# Presentation 리팩터링 백로그

## 목적

이 문서는 `Presentation`의 실제 코드 감사를 바탕으로, 사용자 기능·문구·Figma UI·API 계약을 바꾸지 않는 구조 리팩터링 범위를 관리한다. 장기 규칙의 원본은 [PRESENTATION.md](../Architecture/Layers/PRESENTATION.md)이며, 이 문서는 개별 파일의 관찰 결과·우선순위·진행 상태만 관리한다.

## 사용 방법

- MUST 실제 리팩터링 전에 이 문서에서 대상 항목의 근거·영향·검증을 확인한다.
- MUST 구조 리팩터링과 기능 변경을 같은 커밋에 섞지 않는다.
- MUST 항목 완료 시 상태와 검증 결과를 갱신한다.
- MUST `Core/Architecture/MVICore`, `Core/Coordinator`, `Core/Network`, `Data/Local` 수정이 필요한 항목은 별도 사용자 승인을 받는다.
- SHOULD 파일 줄 수만으로 분리하지 않고, 독립 State·Action·Effect 또는 독립 UI 계약이 있는지 먼저 확인한다.

## 우선순위 기준

| 우선순위 | 기준 |
| --- | --- |
| P0 | Presentation 규칙 위반, 직접 I/O·SDK 호출, lifecycle·cancellation 누락, 중복 요청·stale response·개인정보 위험 |
| P1 | root 과밀, child ownership 불명확, sibling 결합, 반복된 조립·route payload, 책임이 섞인 Service·Adapter |
| P2 | 실제 분리 가능성이 확인된 장문 파일, TODO/FIXME, naming, private extension/MARK, Geometry·화면 크기 의존성 검토 |

## 감사 결과

### P0 — 동작 위험 또는 경계 위반

| 상태 | 대상 | 관찰 근거 | 목표 구조 | 검증 |
| --- | --- | --- | --- | --- |
| 미착수 | `Home/BottomSheet/CourseDetail/CourseDetailBottomSheetView.swift` | View가 `RouteGuidanceService.shared`를 직접 조회하고, `Task`에서 외부 앱 실행·연습 측정 시작·회원 조회를 처리한다. View가 lifecycle-bound 제품 I/O를 소유하지 않는 규칙과 충돌한다. | 길안내 선택·설정 복귀·측정 시작·외부 앱 실행 결과를 reducer action과 feature service/adapter로 이동한다. View는 dialog 표시와 action 전달만 맡긴다. | 코스 길안내 선택, 위치 권한 거부·허용, Live Activity 권한 설정 복귀, 연속 탭, 외부 앱 실패·복귀 |
| 미착수 | `Home/BottomSheet/ParkingDetail/ParkingDetailBottomSheetView.swift` | 코스 상세와 같은 방식으로 singleton 조회와 `Task` 기반 길안내·측정 I/O가 View에 있다. 두 구현의 정책도 복제되어 있다. | 코스와 주차장이 공유할 수 있는 길안내 intent/payload를 BottomSheet reducer와 feature service로 통합한다. 단, UI와 장소별 정책은 유지한다. | 주차장 길안내, 앱 미설치, 설정 복귀, 활성 측정 종료/계속, 중복 탭 |
| 미착수 | `My/MyReducer.swift` | Reducer가 `UserApi.shared.logout` SDK callback을 직접 호출한다. reducer의 Domain contract 의존 및 Effect owner 원칙과 충돌한다. | Login/Auth feature service 또는 주입된 logout contract로 감싸고, reducer는 Effect 결과만 받는다. | 로그아웃 성공·실패·취소, 세션 초기화, 화면 전환, 늦은 callback |
| 완료 | `CourseRegistration` snackbar·비동기 소유권 | root·튜토리얼·상세 화면의 3초 dismiss timer가 View `.task`에 있었고, 지도·핀·검색·폼 요청의 화면 이탈 뒤 결과 반영 위험이 있었다. | snackbar dismiss는 각 Reducer Effect와 revision으로, 지도·핀·검색·폼 요청은 cancellation ID와 session/request ID로 소유권을 정리했다. | 오류 연속 발생, 화면 이탈·재진입, 위치·검색·역지오코딩·등록 응답 지연 |

### P1 — ownership·응집도 정리

| 상태 | 대상 | 관찰 근거 | 목표 구조 | 검증 |
| --- | --- | --- | --- | --- |
| 미착수 | `Home/HomeReducer.swift` | 822줄의 root가 Map·Search·BottomSheet를 조립하면서 지도 lifecycle·marker rendering·위치·검색·최종 callback 정책까지 함께 가진다. child reducer는 이미 있으나 root의 중재 책임이 과밀하다. | Map·Search·BottomSheet Delegate를 명시하고 root에는 조립·최종 route·최소 cross-feature intent만 남긴다. | 지도 초기화, 위치 권한, 마커, 검색 결과 선택, 상세 시트·후기 진입/복귀 |
| 미착수 | `Home/HomeView.swift` | 736줄이며 Home dependency, overlay, full-screen 전환, callback revision 처리, Snackbar를 함께 조립한다. initializer가 다수의 개별 callback과 state를 받는다. | route/presentation payload를 묶고 화면별 host/overlay 조립을 책임 단위로 분리한다. root View의 제품 판단을 줄인다. | search·course detail·review overlay·location alert·tab visibility·scene 전환 |
| 미착수 | `Home/BottomSheet/HomeBottomSheetView.swift` | 768줄이며 drag progress, settle task, safe area, detail·추천 목록·dialog 조립을 같이 소유한다. 단일 custom sheet의 gesture 상태는 유지해야 한다. | gesture/height 관찰 UIKit 또는 SwiftUI bridge와 화면 조립을 분리한다. reducer route와 View-local drag 값의 경계를 명시한다. | 느린 drag, dismiss/rest/expanded settle, 앱 전환 복귀, SE·대형 기기 safe area |
| 미착수 | `Home/Search/HomeSearchReducer.swift` | 568줄에 검색어, 지역·장소 결과, 최근 검색어, 선택 결과와 cursor/요청 최신성 정책이 함께 있다. | 독립 state/action/effect를 기준으로 RecentSearch와 SearchResult를 named child 또는 명확한 내부 책임으로 분리한다. | 입력 debounce, 최근 검색어 선택·재정렬, 지역 이동, 빈 결과, 빠른 연속 검색 |
| 미착수 | `Home/BottomSheet/CourseDetail/Review/CourseReviewReducer.swift` | 후기 조회 cache, level 선택, 페이지네이션, 신고·차단 결과 반영, 삭제/refresh를 한 reducer가 소유한다. | preview·목록 cache와 report/block child flow의 delegate 경계를 재검토한다. CourseDetail root가 Review 내부 state를 직접 판단하지 않게 유지한다. | level 전환, cache 재사용, cursor, 신고·차단, 늦은 응답, 상세 닫힘 |
| 완료 | `CourseRegistration` root·하위 흐름 | 767줄 root가 route switch 외에 지도 선택·핀 편집 layout과 다수 callback을 소유했고, 검색 화면이 내부 Store를 생성했다. | root는 route 조립과 외부 revision 전달만 맡기고, 지도 선택·핀 편집은 각 SubPage View, 검색은 부모 State가 소유하는 child flow로 이동했다. | 튜토리얼, 장소 검색, 핀 편집, 경유지 추가·삭제, 상세 제출·이탈 확인 |
| 미착수 | `My/SubPage/MyPosts/MyPostsReducer.swift` | 585줄에 코스/후기 두 목록, 필터, 각 cursor, 두 삭제 flow, snackbar, 후기 수정·연습기록 조건을 함께 가진다. | CoursePosts와 ReviewPosts의 상태·pagination·delete를 named child reducer 또는 명확한 책임 단위로 분리하고 MyPosts root는 탭·최종 delegate만 소유한다. | 탭 전환, 필터, cursor, 삭제 dialog·실패, 수정 진입, 연습기록 유무 |
| 미착수 | `PracticeTracking/Service/PracticeTrackingService.swift` | 423줄 singleton이 위치 측정, session 저장, 인증, background activity, Live Activity 호출을 함께 소유한다. | 위치 runtime adapter, session policy, Live Activity bridge의 책임을 재검토한다. singleton 제거는 별도 결정이며 현재 configure·저장 key는 유지한다. | 앱 재시작 복구, background/foreground, 인증 거리, Live Activity start/sync/end, 중복 세션 |
| 미착수 | `Login/Service/SocialLoginService.swift` | Kakao SDK callback, timeout task, Apple/Kakao 진입과 UIKit scene 탐색을 한 service가 소유한다. | SDK adapter와 social credential orchestration의 cancellation·timeout ownership을 분리할 수 있는지 검토한다. | Kakao 앱/웹 fallback, Apple 취소, timeout, 중복 로그인, 화면 이탈 |
| 완료 | `Review` | root에는 `ReviewView`·`ReviewReducer`만 두고, `Flow`·`Prompt`·`Writing`·`SkipReason`으로 책임을 분리했다. | 실제 feature 작업마다 typed Delegate·stale response 규칙을 회귀 점검한다. | prompt, 작성/수정, 미방문 사유, 완료·취소·refresh |
| 완료 | `PracticeTracking` | root View·Reducer와 `Adapter`·`Return`·`Service`·`LiveActivity`의 경계를 정리했다. | 이후 singleton과 session store 이동은 Domain/Data 단계에서 별도 결정한다. | 앱 복귀, 측정 계속/종료, 후기 권유, Live Activity |

### P2 — 구조·표현·유지보수 개선

| 상태 | 대상 | 관찰 근거 | 목표 구조 | 검증 |
| --- | --- | --- | --- | --- |
| 미착수 | `Home` 경로 이동 전체 | 현재 worktree에 기존 경로 삭제와 `Home/SubView/...` 추가가 함께 존재한다. 구조 이동 완료 전에는 중복·누락을 확정할 수 없다. | filesystem-synchronized group과 실제 import·참조를 확인해 `Map`, `Search`, `BottomSheet` 직접 경로로 단일화한다. | Xcode group, build membership, 이전 경로 참조 0건 |
| 미착수 | `My/SubPage/MyPosts/MyPostsView.swift` | dropdown anchor와 `GeometryReader`로 menu 위치·width를 계산한다. | overlay anchor가 필요한지 확인하고, 가능하면 component의 intrinsic layout·alignment로 축소한다. | 긴 닉네임·메뉴 문구, 작은 기기, 스크롤·빈 영역 tap |
| 미착수 | `Home/BottomSheet/CourseDetail/SubPage/CourseDetailExpandedPage.swift` | dropdown anchor 및 `GeometryReader`가 상세 화면에 있다. | 드롭다운 overlay의 최상단 표시와 layout 측정 필요성을 재검토한다. | 후기 menu·level dropdown, safe area, compact/large device |
| 미착수 | `CourseRegistration/SubPage/Tutorial/CourseRegistrationTutorialView.swift` | tutorial progress 표현에 `GeometryReader`가 있다. | `Layout`, flexible frame, `scaleEffect` 등 대체 가능성을 확인한다. | 긴 글자·Dynamic Type·화면 회전 없이 compact/large layout |
| 미착수 | `Onboarding/Component/OnboardingAnalysisDialog.swift` | 직접 `UIScreen.main.bounds.height`를 사용한다. | safe area와 컨테이너 기반 max height로 전환할 수 있는지 검토한다. | SE·대형 iPhone, keyboard, Dynamic Type |
| 미착수 | `Login/LoginView.swift` | 직접 `UIScreen.main.bounds.width`를 사용한다. | flexible frame 또는 container layout으로 전환할 수 있는지 검토한다. | SE·대형 iPhone, 긴 로컬라이즈 문구 |
| 미착수 | `CourseRegistration/Service/CourseRegistrationMapService.swift` | Kakao REST reverse geocode의 private response DTO와 `URLSession`을 feature service가 소유한다. 외부 API 전용 구현으로 허용 가능하지만 Search의 Kakao REST service와 contract가 분산됐다. | 공통 abstraction을 강제하지 않고, Kakao REST 요청·오류·DTO가 feature-local로 유지될 근거와 중복만 재검토한다. | 주소 변환 성공·빈 응답·HTTP·취소·API key 누락 |
| 미착수 | `Home/BottomSheet/CourseDetail/Service/KakaoDirectionsService.swift` | Kakao directions request·private DTO·오류 파싱이 feature service에 있다. 외부 SDK/API adapter 경계로는 허용 가능하다. | CourseRegistration Kakao REST와 실제 공통 정책이 확인될 때만 작은 transport helper를 검토한다. | 경유지, 빈 route, HTTP/decoding/network 실패, 좌표 로그 비노출 |
| 미착수 | `Debug/DebugFeatureTestPage.swift` | 350줄 테스트 화면이 Live Activity singleton preview와 계정 관련 debug action을 함께 노출한다. | Debug 전용 intent를 작은 section/component로 분리하고 Release 진입 불가를 정적 확인한다. | Debug build만 노출, Release build 미노출 |
| 미착수 | TODO/FIXME 3건 | `HomeReducer` map interaction 계산 프로퍼티, `HomeView` snackbar, `BottomSheetPanGestureView`의 TODO가 남아 있다. | 각 TODO를 위 항목에 연결하거나 해결·삭제하고, 새로운 TODO는 근거와 제거 조건을 남긴다. | TODO 검색 결과와 관련 기능 smoke test |
| 미착수 | 500줄 이상 파일 | `HomeReducer`, `HomeView`, `HomeBottomSheetView`, `MyPostsReducer`, `HomeSearchReducer`, `CourseDetailExpandedPage`가 500줄 이상이다. | P1 항목의 실제 responsibility 분리 뒤 다시 측정한다. 줄 수 단독 리팩터링은 하지 않는다. | 각 Feature build·핵심 수동 시나리오 |

## 실행 순서

1. P0 길안내 View I/O를 코스·주차장 묶음으로 정리한다.
2. P0 로그아웃 contract와 CourseRegistration snackbar owner를 각각 작은 변경으로 정리한다.
3. Home 경로 이동을 단일화한 뒤 Home root·Map·Search·BottomSheet를 각각 P1 단위로 처리한다.
4. CourseRegistration과 MyPosts를 다단계/목록 child ownership 기준으로 처리한다.
5. PracticeTracking·Login Service와 P2 layout·TODO를 기능 QA 이후 처리한다.

## 공통 검증

- MUST 코드 구조 변경 뒤 `Rodi Dev` Debug build와 `git diff --check`를 실행한다.
- MUST 각 항목의 표에 적힌 수동 시나리오를 해당 변경 단위에서 확인한다.
- MUST 테스트 target이 없으므로 자동 테스트 통과라고 기록하지 않는다.
- SHOULD 구조 이동 전후에 `rg`로 이전 경로·심볼 참조가 남지 않았는지 확인한다.
