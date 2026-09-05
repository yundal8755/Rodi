# 윤달 HandOff

## Current

- 기준 저장소·브랜치: 현재 작업 저장소의 `dev`
- 기준 커밋: `416cefa5a34e9441280e456fd1405fd47e04e1c9`
- 작성일: 2026-09-05
- 현재 작업: 활성 작업 문서 정비와 AI 탐색 범위 개선

## Recent Work

- AGENTS와 분야별 활성 문서의 중복 규칙과 오래된 기준을 정리했다.
- 2026-08-19~20 리팩터링·코드리뷰 기록과 이전 HandOff 상세 내역을 Archive로 이동해, 현재 작업 상태와 과거 근거를 분리했다.
- 문서 탐색의 확장·종료 조건, skill 선택 경계와 결과 품질 측정 기준을 추가했다.
- API 전체 인벤토리를 Archive에 보존하고, endpoint 검증 기록은 API 가이드에 통합했다.
- 결함·검증·구조 개선·API 계약·기능 후보·글쓰기 작업을 `Docs/TODO.md`의 단일 상태 원본으로 통합했다.
- Architecture에 Layer 계약과 한국어 코드 주석 기준을 합치고, API 연결 기록은 API 가이드에 흡수했다.
- 발표·회고 자료 3개를 Archive로 옮기고 GPS 테스트 가이드를 `Docs/Tests/`로 이동해 활성 Docs를 7개로 유지했다.
- AGENTS의 문서 안내를 단일 표로 합치고 Archive·Handoff·TODO 탐색 조건과 UI 가이드의 불일치 판단 기준을 맞췄다.

## Next

- [TODO](../Docs/TODO.md)의 대상 ID를 기준으로 다음 작업을 선택하고, 완료된 항목은 검증 뒤 삭제한다.

## Verification

- `bash Scripts/validate_documentation.sh`에서 Markdown 106개 링크와 폐기 문서 참조 검사를 통과했다.
- `git diff --check`를 통과했다.
- 이동 문서의 본문·TODO ID 보존과 UI·API·Reducer·배포·GPS 요청 5종의 문서 선택 규칙을 정적으로 확인했다. 실제 AI 작업의 토큰 사용량·결과 품질은 측정하지 않았다.
- 이번 작업은 문서·문서 검사 스크립트·Handoff만 변경하므로 Xcode build와 실기기 QA는 실행하지 않았다.

## Archive

- 이전 상세 기록: [윤달 HandOff 2026-09-05](archive/윤달_HandOff_2026-09-05.md)
