import SwiftUI

struct ReviewFormPageTwoView: View {
    let state: ReviewReducer.State
    let send: (ReviewReducer.Action) -> Void

    @State private var isContentFocused = false

    var body: some View {
        VStack(spacing: 0) {
            ReviewFormHeader(
                title: "후기 남기기",
                showsBack: true,
                backAction: { send(.backTapped) },
                closeAction: { send(.closeTapped) }
            )
            .zIndex(1)
            VStack(alignment: .leading, spacing: 0) {
                Text("연습 방법")
                    .rodiTypography(.body1SemiBold)
                    .foregroundStyle(RodiColor.black)

                HStack(spacing: 6) {
                    methodButton(.solo)
                    methodButton(.accompanied)
                }
                .padding(.top, 12)
                Text("후기 작성")
                    .rodiTypography(.body1SemiBold)
                    .foregroundStyle(RodiColor.black)
                    .padding(.top, 40)
                reviewTextEditor
                Text("\(state.content.count) / 150")
                    .rodiTypography(.body3Medium)
                    .foregroundStyle(RodiColor.gray600)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 4)
                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismissContentKeyboard)
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            PrimaryBottomButton(
                title: "완료",
                isEnabled: state.canSubmit,
                showsDivider: true,
                action: { send(.submitTapped) }
            )
        }
        .background(RodiColor.white)
    }
}

// MARK: - Component
private extension ReviewFormPageTwoView {

    var reviewTextEditor: some View {
        ReviewTextEditor(
            text: contentBinding,
            characterLimit: 150,
            isFocused: $isContentFocused
        )
            .frame(height: 100)
            .background(RodiColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isContentFocused ? RodiColor.gray850 : RodiColor.gray300, lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                if state.content.isEmpty {
                    Text("자유롭게 후기를 작성해주세요.")
                        .rodiTypography(.body3Medium)
                        .foregroundStyle(RodiColor.gray500)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .padding(.top, 12)
    }

    func methodButton(_ method: ReviewPracticeMethod) -> some View {
        ReviewChoiceButton(title: method.title, isSelected: state.practiceMethod == method) {
            send(.practiceMethodSelected(method))
        }
    }

    var contentBinding: Binding<String> {
        Binding(
            get: { state.content },
            set: { send(.contentChanged($0)) }
        )
    }

    func dismissContentKeyboard() {
        isContentFocused = false
    }
}
