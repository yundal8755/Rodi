import Foundation

struct CourseRegistrationTutorialReducer: Reducer {
    struct State: Equatable {
        var page = 0
        var isCompleting = false
        var errorMessage: String?
    }

    enum Action {
        case pageChanged(Int)
        case pageTapped
        case completionTapped
        case completionFinished(Result<Void, NetworkError>)
        case errorDismissed
        case delegate(Delegate)
    }

    enum Delegate {
        case completed
    }

    private let memberRepository: MemberRepository

    init(memberRepository: MemberRepository) {
        self.memberRepository = memberRepository
    }

    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .pageChanged(let page):
            state.page = min(max(page, 0), 2)

        case .pageTapped:
            guard state.page < 2 else { return .none }
            state.page += 1

        case .completionTapped:
            guard state.page == 2, !state.isCompleting else { return .none }
            state.isCompleting = true
            state.errorMessage = nil
            return .run { send in
                do {
                    _ = try await memberRepository.completeCourseTutorial()
                    await send(.completionFinished(.success(())))
                } catch let error as NetworkError {
                    await send(.completionFinished(.failure(error)))
                } catch {
                    await send(.completionFinished(.failure(.unknown(errorCode: "unknown"))))
                }
            }

        case .completionFinished(let result):
            state.isCompleting = false
            switch result {
            case .success:
                return .send(.delegate(.completed))
            case .failure:
                state.errorMessage = "튜토리얼 완료를 저장하지 못했어요. 다시 시도해 주세요."
            }

        case .errorDismissed:
            state.errorMessage = nil

        case .delegate:
            return .none
        }

        return .none
    }
}
