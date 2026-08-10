import SwiftUI

struct ReviewSkipReasonView: View {
    private static let detailFieldID = "review-skip-reason-detail"

    let state: ReviewReducer.State
    let send: (ReviewReducer.Action) -> Void

    @FocusState private var isDetailFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ReviewFormHeader(
                title: "미방문 사유",
                showsBack: false,
                closeAction: { send(.closeTapped) }
            )
            .zIndex(1)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("왜 연습을 다녀오지 않았나요?")
                            .rodiTypography(.heading2)
                            .foregroundStyle(RodiColor.black)

                        Text("이유를 알려주시면 더 나은 코스를 추천해드릴게요!")
                            .rodiTypography(.body3Medium)
                            .foregroundStyle(RodiColor.gray600)
                            .padding(.top, 8)

                        formContent
                            .padding(.top, 28)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissDetailKeyboard)
                .onChange(of: isDetailFocused) { isFocused in
                    guard isFocused else { return }
                    DispatchQueue.main.async {
                        withAnimation {
                            scrollProxy.scrollTo(Self.detailFieldID, anchor: .bottom)
                        }
                    }
                }
            }

            if !isDetailFocused {
                PrimaryBottomButton(
                    title: "완료",
                    isEnabled: state.canSubmitSkipReason,
                    showsDivider: true,
                    action: { send(.skipReasonSubmitTapped) }
                )
            }
        }
        .background(RodiColor.white)
    }
}

// MARK: - Content
private extension ReviewSkipReasonView {

    @ViewBuilder
    var formContent: some View {
        switch state.skipReasonFormState {
        case .idle, .loading:
            ProgressView()
                .tint(RodiColor.primary)
                .frame(maxWidth: .infinity, minHeight: 184)

        case .loaded(let form):
            VStack(alignment: .leading, spacing: 16) {
                ForEach(form.options) { option in
                    ReviewRadioOption(
                        title: option.label,
                        isSelected: state.selectedSkipReason?.code == option.code,
                        action: { send(.skipReasonSelected(option)) }
                    )
                }

                if let selectedSkipReason = state.selectedSkipReason,
                   selectedSkipReason.requiresTextInput {
                    detailField(for: selectedSkipReason)
                        .padding(.top, 4)
                        .id(Self.detailFieldID)
                }
            }

        case .failed:
            VStack(spacing: 12) {
                Text("미방문 사유를 불러오지 못했어요.")
                    .rodiTypography(.body3Medium)
                    .foregroundStyle(RodiColor.gray600)

                Button {
                    send(.skipReasonFormRetryTapped)
                } label: {
                    Text("다시 시도")
                        .rodiTypography(.buttonMedium)
                }
                .foregroundStyle(RodiColor.primary)
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, minHeight: 184)
        }
    }

    func detailField(for option: PracticeSkipReasonOption) -> some View {
        VStack(spacing: 4) {
            RodiTextField(
                text: detailBinding,
                placeholder: option.textInputPlaceholder ?? "이유를 작성해주세요",
                characterLimit: ReviewSkipReasonDetailConfiguration.characterLimit,
                isFocused: $isDetailFocused
            )
            .padding(.vertical, 14)
            .background(RodiColor.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isDetailFocused ? RodiColor.gray850 : RodiColor.gray300, lineWidth: 1)
            }

            Text("\(state.skipReasonDetail.count) / \(ReviewSkipReasonDetailConfiguration.characterLimit)")
                .rodiTypography(.body3Medium)
                .foregroundStyle(RodiColor.gray600)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.bottom, 48)
    }

    var detailBinding: Binding<String> {
        Binding(
            get: { state.skipReasonDetail },
            set: { send(.skipReasonDetailChanged($0)) }
        )
    }

    func dismissDetailKeyboard() {
        isDetailFocused = false
    }
}
