# RODI UI · Figma Guide

## 목적과 적용 범위

이 문서는 Figma node를 근거로 RODI UI를 구현하거나 검토할 때 디자인 근거를 수집하고 차이를 판정하는 절차를 정의한다.

- MUST Figma 링크만 전달된 설명·분석 요청과 실제 구현 요청을 구분한다. 링크 자체를 파일 수정 권한으로 해석하지 않는다.
- MUST UI의 시각 계약은 대상 node의 screenshot과 속성으로, 현재 기능 동작은 live code로 확인한다.
- MUST 선택된 chip이나 비활성 button 한 상태만 보고 단일·복수 선택, 필수 입력, API 호출 같은 기능 정책을 추정하지 않는다.
- SHOULD Reducer 소유권이나 foldering 변경이 필요할 때만 [ARCHITECTURE.md](../Architecture/ARCHITECTURE.md)를 추가로 읽는다.

## Figma 근거 확인

1. MUST URL에서 구현 대상 `node-id`를 확인하고, 현재 실행 환경의 필수 Figma 지침을 읽는다.
2. MUST 대상 node의 design context와 screenshot을 확인한다. 생성된 React·Tailwind는 hierarchy·문구·asset 단서로만 사용한다.
3. MUST device bezel, status bar, home indicator 같은 기기 chrome을 앱 asset이나 custom View로 옮기지 않는다.
4. MUST 같은 작업에서 이미 확인했고 변경되지 않은 node를 반복 조회하지 않는다. 결과 누락·잘림·디자인 변경·별도 상태 확인이 필요할 때만 추가 조회한다.
5. MUST context를 얻지 못한 page·canvas node라면 내부의 실제 frame을 찾아 다시 조회한다.

## 기존 구현 탐색과 차이 판단

- MUST 기존 화면 수정이면 화면 고유 문구나 예상 심볼을 `rg -l`로 검색하고, 대응 View와 직접 사용되는 Component부터 읽는다.
- MUST 신규 화면이면 인접 Feature의 실제 진입 경로와 가장 유사한 화면을 확인한다. 기존 화면이 있다는 전제로 검색 결과를 해석하지 않는다.
- MUST 화면 구조, interaction, navigation, loading·empty·error·success 상태를 구분하고 Figma에 없는 동작은 live code나 명시된 제품 요구사항으로 확인한다.
- MUST Figma와 현재 구현이 다르면 시각 변경, 기능 변경, 서버 계약 변경을 구분한다. 현재 코드를 근거로 디자인 계약을 자동 변경하지 않는다.
- SHOULD 후보 파일을 좁힌 뒤 필요한 심볼과 구간만 읽고, 변경 위치·유지할 계약·검증 방법이 확정되면 탐색을 멈춘다.

## Token·Component·Asset 적용

- MUST RODI의 token·Component·custom UI 계약은 `.agents/skills/rodi-swiftui`에서 확인하고, 같은 의미의 기존 구현을 우선 사용한다.
- MUST 새 token이나 공통 Component는 현재 요청에서 실제 중복이나 공유 책임이 확인된 경우에만 추가한다.
- MUST 단순 UI 변경을 캐싱·성능 최적화·공통 Component 개편으로 확대하지 않는다.
- MUST asset 재사용 여부를 이름만으로 판단하지 않고 glyph, 크기, 투명 여백, rendering mode를 Figma export와 대조한다.
- MUST 없는 asset은 Figma가 제공한 원본 bytes를 의미 기반 이름으로 catalog에 추가한다. 임시 asset URL이나 임의로 다시 그린 대체물을 source에 남기지 않는다.
- MUST Figma 문구가 안전·사고 방지를 보장하면 `AGENTS.md`의 제품 안전 제약에 맞춰 처리한다.

## 레이아웃 판정

- MUST Figma의 x·y 좌표나 viewport 크기를 화면 전체 고정 frame과 `.position`으로 복제하지 않는다.
- MUST `GeometryReader`, 측정용 `PreferenceKey`, 직접 `UIScreen.main`, 반복적인 `.offset`을 일반적인 화면 배치 수단으로 사용하지 않는다.
- SHOULD stack, grid, scroll, alignment, flexible frame, safe-area API와 기존 project abstraction 순서로 적응형 구조를 선택한다.
- MUST 측정 API가 필요하면 기존 UI 계약과 SDK·gesture 제약으로 대체할 수 없는 이유와 영향 화면을 확인한다.
- MAY 명확한 icon·Component 자체 크기와 장식 목적의 제한된 위치값은 고정할 수 있다.

## 검증과 보고

- MUST 변경 영향에 맞춰 hierarchy, spacing, typography, color, corner, asset, selected·disabled·error 상태와 interaction을 확인한다.
- MUST 신규 화면·입력·scroll 변경에서는 compact·large device, safe area, keyboard, 긴 한국어 문구, Dynamic Type, VoiceOver tap target을 확인한다.
- SHOULD 동일 상태의 screenshot을 Figma와 나란히 비교하고 의도적으로 다른 부분과 확인하지 못한 상태를 보고한다.
- MUST 코드·구조 변경 뒤 `AGENTS.md`의 Dev Debug build를 실행한다. 자동 테스트를 실행하지 않았다면 테스트 통과로 보고하지 않는다.
- MUST 단순 색상·간격 변경과 신규 interaction 화면에 동일한 전체 QA 목록을 기계적으로 적용하지 않는다.
