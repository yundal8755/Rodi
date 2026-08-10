import SwiftUI

struct ReviewFlowView: View {
    let state: ReviewReducer.State
    let send: (ReviewReducer.Action) -> Void

    var body: some View {
        ZStack {
            if showsFormBackground {
                RodiColor.white
                    .ignoresSafeArea()
            }

            currentPage

            if state.presentation == .discardConfirmation {
                ReviewDiscardConfirmationView(send: send)
            }

            if state.presentation == .skipReasonCompletion {
                ReviewSkipReasonCompletionView(send: send)
            }

            if state.presentation == .completion {
                ReviewCompletionView(send: send)
            }
        }
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Page
private extension ReviewFlowView {

    var showsFormBackground: Bool {
        switch state.presentation {
        case .formPage1, .formPage2, .skipReasonForm, .discardConfirmation, .completion, .skipReasonCompletion:
            true

        case .hidden, .preparing, .prompt:
            false
        }
    }

    @ViewBuilder
    var currentPage: some View {
        switch state.presentation {
        case .hidden:
            EmptyView()
        case .preparing:
            ReviewPreparingView()

        case .prompt:
            ReviewPromptView(
                target: state.target,
                isSubmittingVisit: state.isSubmittingVisit,
                send: send
            )

        case .formPage1:
            ReviewFormPageOneView(state: state, send: send)

        case .formPage2, .completion:
            ReviewFormPageTwoView(state: state, send: send)

        case .skipReasonForm, .skipReasonCompletion:
            ReviewSkipReasonView(state: state, send: send)

        case .discardConfirmation:
            previousFormPage

        }
    }

    @ViewBuilder
    var previousFormPage: some View {
        switch state.pageBeforeDiscard {
        case .formPage2:
            ReviewFormPageTwoView(state: state, send: send)
        case .skipReasonForm:
            ReviewSkipReasonView(state: state, send: send)
        case .formPage1, .hidden, .preparing, .prompt, .discardConfirmation, .completion, .skipReasonCompletion, .none:
            ReviewFormPageOneView(state: state, send: send)
        }
    }
}
