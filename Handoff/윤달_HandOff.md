# 윤달 HandOff

## Current

- 브랜치: `release/1.4.1`
- 작업 상태: Presentation 리팩터링 진행 중

## Recent Work

- CourseRegistration root View를 route 조립 중심으로 축소했다.
- 지도 선택·핀 수정 View와 공통 Component를 책임 위치로 분리했다.
- 장소 검색 State를 부모 reducer가 소유하도록 전환하고, snackbar·비동기 요청의 취소 및 stale-result 방어를 reducer Effect로 정리했다.
- HandOff 운영 규칙을 도입하고, 중복된 루트 TODO를 `Docs/TODO`로 이관해 문서 원본을 단일화했다.

## Next

- CourseRegistration 튜토리얼, 검색, 핀 수정, 등록 재시도·이탈 흐름을 수동 QA한다.
- Presentation 리팩터링 backlog의 다음 Feature 우선순위를 확인한다.

## Validation

- `Rodi Dev` Debug build 성공
- `git diff --check` 통과
- 수동 QA 미실행
