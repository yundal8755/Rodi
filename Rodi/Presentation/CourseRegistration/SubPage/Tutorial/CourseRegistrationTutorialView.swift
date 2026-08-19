import SwiftUI

struct CourseRegistrationTutorialView: View {
    let state: CourseRegistrationTutorialReducer.State
    let send: (CourseRegistrationTutorialReducer.Action) -> Void

    var body: some View {
        VStack(spacing: 0) {
            CourseRegistrationHeader(title: "코스 등록 방법", closeAction: { send(.closeTapped) })
            StepProgressView(activeCount: state.page + 1, totalCount: 3)
            TabView(
                selection: Binding(
                    get: { state.page },
                    set: { send(.pageChanged($0)) }
                )
            ) {
                ForEach(CourseRegistrationTutorialPage.allCases, id: \.rawValue) { page in
                    CourseRegistrationTutorialPageView(page: page)
                        .tag(page.rawValue)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if page.rawValue < 2 {
                                send(.pageTapped)
                            }
                        }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if state.page == 2 {
                PrimaryBottomButton(
                    title: state.isCompleting ? "저장 중..." : "완료",
                    isEnabled: !state.isCompleting,
                    showsDivider: true,
                    action: { send(.completionTapped) }
                )
                .shadow(color: RodiColor.black.opacity(0.08), radius: 4, x: 0, y: -3)
            }
        }
        .background(RodiColor.white)
        .rodiSnackbar(message: state.errorMessage)
        .onDisappear { send(.deactivated) }
    }
}

private enum CourseRegistrationTutorialPage: Int, CaseIterable {
    case mapPlacement
    case startSelection
    case pinEditing

    var title: String {
        switch self {
        case .mapPlacement: "지도를 움직여 핀을 놓을 위치를 정하고"
        case .startSelection: "아래 ‘출발지 선택'을 눌러, 위치를 선택해요"
        case .pinEditing: "건물이 아닌, 도로 위에 위치 시켜주세요."
        }
    }

    var description: String {
        switch self {
        case .mapPlacement: "출발지 → 도착지 → 경유지 순서로 코스를 구성해요."
        case .startSelection: "건물이 아닌, 도로 위에 위치 시켜주세요."
        case .pinEditing: "‘핀 수정하기' 화면으로 이동할 수 있어요."
        }
    }
}

private struct CourseRegistrationTutorialPageView: View {
    let page: CourseRegistrationTutorialPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(page.title)
                        .rodiTypography(.heading2)
                        .foregroundStyle(RodiColor.black)
                    Text(page.description)
                        .rodiTypography(.body3Medium)
                        .foregroundStyle(Color(hex: 0xFF966F))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)

                CourseRegistrationTutorialReferenceImage(page: page)
                    .padding(.bottom, 24)
            }
            .padding(.top, 4)
        }
    }
}

private struct CourseRegistrationTutorialReferenceImage: View {
    let page: CourseRegistrationTutorialPage

    var body: some View {
        GeometryReader { proxy in
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: proxy.size.width * 0.72)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .aspectRatio(CGFloat(552) / (CGFloat(1078) * 0.72), contentMode: .fit)
    }

    private var imageName: String {
        switch page {
        case .mapPlacement: "img_course_tutorial_step_1"
        case .startSelection: "img_course_tutorial_step_2"
        case .pinEditing: "img_course_tutorial_step_3"
        }
    }
}
