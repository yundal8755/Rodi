import CoreLocation
import Foundation

struct CourseRegistrationDetailsReducer: Reducer {
    struct State: Equatable {
        var context: CourseRegistrationDetailsContext?
        var loadState: CourseRegistrationDetailsLoadState = .idle
        var draft = CourseRegistrationDetailsDraft()
        var loadRevision = 0
        var isDiscardConfirmationPresented = false
        var isSubmitting = false
        var isCompletionPresented = false
        var alertToast: CourseRegistrationAlertToastState?
        var alertToastRevision = 0

        var isSubmitEnabled: Bool {
            guard case let .loaded(form) = loadState,
                  !isSubmitting,
                  !draft.selectedCategoryCodes.isEmpty,
                  !draft.selectedPracticeTypeCodes.isEmpty
            else {
                return false
            }

            let requiredInputs: [(CourseRegistrationTextInputSpec, String)] = [
                (form.inputs.caution, draft.caution),
                (form.inputs.description, draft.description)
            ]
            let hasRequiredInputs = requiredInputs.allSatisfy { spec, value in
                !spec.required || !trimmed(value).isEmpty
            }
            return hasRequiredInputs && trimmed(draft.description).count >= 10
        }

        private func trimmed(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    enum Action {
        case start(CourseRegistrationDetailsContext)
        case formLoaded(Int, Result<CourseRegistrationForm, NetworkError>)
        case retryTapped
        case categoryTapped(String)
        case practiceTypeTapped(String)
        case cautionChanged(String)
        case descriptionChanged(String)
        case backTapped
        case discardConfirmed
        case discardCancelled
        case submitTapped
        case submissionFinished(Result<CourseRegistrationResult, NetworkError>)
        case completionConfirmed
        case alertToastDismissed(Int)
        case delegate(Delegate)
    }

    enum Delegate {
        case backRequested
        case completionConfirmed
    }

    private let courseRepository: CourseRepository

    init(courseRepository: CourseRepository) {
        self.courseRepository = courseRepository
    }

    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .start(let context):
            state = .init(context: context)
            return loadRegistrationForm(state: &state)

        case .formLoaded(let revision, let result):
            guard state.loadRevision == revision else { return .none }
            switch result {
            case .success(let form):
                state.loadState = .loaded(form)
            case .failure:
                state.loadState = .failed
            }

        case .retryTapped:
            guard !state.isSubmitting else { return .none }
            return loadRegistrationForm(state: &state)

        case .categoryTapped(let categoryCode):
            guard case let .loaded(form) = state.loadState,
                  let category = form.practiceType.categories.first(where: { $0.code == categoryCode })
            else {
                return .none
            }

            if state.draft.selectedCategoryCodes.contains(category.code) {
                state.draft.selectedCategoryCodes.remove(category.code)
                if form.practiceType.categories.first?.code != category.code {
                    let categoryTypeCodes = Set(category.practiceTypes.map(\.code))
                    state.draft.selectedPracticeTypeCodes.removeAll { categoryTypeCodes.contains($0) }
                }
            } else {
                state.draft.selectedCategoryCodes.insert(category.code)
            }

        case .practiceTypeTapped(let practiceTypeCode):
            guard case let .loaded(form) = state.loadState,
                  let category = form.practiceType.categories.first(where: {
                      $0.practiceTypes.contains(where: { $0.code == practiceTypeCode })
                  })
            else {
                return .none
            }

            let isDefaultCategory = form.practiceType.categories.first?.code == category.code
            guard isDefaultCategory || state.draft.selectedCategoryCodes.contains(category.code) else {
                return .none
            }

            if let index = state.draft.selectedPracticeTypeCodes.firstIndex(of: practiceTypeCode) {
                state.draft.selectedPracticeTypeCodes.remove(at: index)
            } else if state.draft.selectedPracticeTypeCodes.count < form.practiceType.maxSelect {
                state.draft.selectedPracticeTypeCodes.append(practiceTypeCode)
            } else {
                showAlert(form.practiceType.maxSelectExceededMessage, state: &state)
            }

        case .cautionChanged(let value):
            state.draft.caution = String(value.prefix(CourseRegistrationDetailsTextLimit.caution))

        case .descriptionChanged(let value):
            state.draft.description = String(value.prefix(CourseRegistrationDetailsTextLimit.description))

        case .backTapped:
            guard !state.isSubmitting else { return .none }
            if state.draft.isDirty {
                state.isDiscardConfirmationPresented = true
            } else {
                return finishBack(state: &state)
            }

        case .discardConfirmed:
            guard state.isDiscardConfirmationPresented else { return .none }
            state.isDiscardConfirmationPresented = false
            return finishBack(state: &state)

        case .discardCancelled:
            state.isDiscardConfirmationPresented = false

        case .submitTapped:
            guard !state.isSubmitting,
                  case let .loaded(form) = state.loadState,
                  state.isSubmitEnabled,
                  validateInputLengths(form: form, state: &state),
                  let context = state.context,
                  let submission = courseSubmission(context: context, draft: state.draft)
            else {
                return .none
            }

            state.isSubmitting = true
            RodiAnalytics.track(
                .courseRegistrationSubmitted(
                    waypointCount: context.waypoints.count,
                    practiceTypeCount: state.draft.selectedPracticeTypeCodes.count,
                    hasCaution: !trimmed(state.draft.caution).isEmpty
                )
            )
            return .run { send in
                do {
                    let result = try await courseRepository.register(submission)
                    await send(.submissionFinished(.success(result)))
                } catch let error as NetworkError {
                    await send(.submissionFinished(.failure(error)))
                } catch {
                    await send(.submissionFinished(.failure(.unknown(errorCode: "unknown"))))
                }
            }

        case .submissionFinished(let result):
            guard state.isSubmitting else { return .none }
            state.isSubmitting = false
            switch result {
            case .success:
                state.isCompletionPresented = true
                RodiAnalytics.track(.courseRegistrationCompleted(waypointCount: state.context?.waypoints.count ?? 0))
            case .failure:
                RodiAnalytics.track(.courseRegistrationFailed(stage: "submission"))
                showAlert("코스를 등록하지 못했어요. 잠시 후 다시 시도해주세요.", state: &state)
            }

        case .completionConfirmed:
            guard state.isCompletionPresented else { return .none }
            state.isCompletionPresented = false
            return .send(.delegate(.completionConfirmed))

        case .alertToastDismissed(let revision):
            guard state.alertToastRevision == revision else { return .none }
            state.alertToast = nil

        case .delegate:
            return .none
        }

        return .none
    }

    private func loadRegistrationForm(state: inout State) -> Effect<Action> {
        state.loadRevision += 1
        let revision = state.loadRevision
        state.loadState = .loading
        return .run { send in
            do {
                let form = try await courseRepository.fetchRegistrationForm()
                await send(.formLoaded(revision, .success(form)))
            } catch let error as NetworkError {
                await send(.formLoaded(revision, .failure(error)))
            } catch {
                await send(.formLoaded(revision, .failure(.unknown(errorCode: "unknown"))))
            }
        }
    }

    private func finishBack(state: inout State) -> Effect<Action> {
        state = .init()
        return .send(.delegate(.backRequested))
    }

    private func validateInputLengths(
        form: CourseRegistrationForm,
        state: inout State
    ) -> Bool {
        let inputs: [(String, CourseRegistrationTextInputSpec, String, Int)] = [
            (form.sections.caution, form.inputs.caution, state.draft.caution, 0),
            (form.sections.description, form.inputs.description, state.draft.description, 10)
        ]

        for (title, spec, value, requiredMinimumLength) in inputs {
            let count = trimmed(value).count
            if spec.required, count == 0 {
                showAlert("\(title)을 입력해 주세요.", state: &state)
                return false
            }

            let minLength = max(spec.minLength ?? 0, requiredMinimumLength)
            if count > 0, count < minLength {
                let message = title == form.sections.description
                    ? "한줄 설명은 \(minLength)자 이상이어야 해요."
                    : "\(title)은 \(minLength)자 이상이어야 해요."
                showAlert(message, state: &state)
                return false
            }
        }

        return true
    }

    private func courseSubmission(
        context: CourseRegistrationDetailsContext,
        draft: CourseRegistrationDetailsDraft
    ) -> CourseRegistrationSubmission? {
        guard let start = context.selectedPlaces[.start],
              let destination = context.selectedPlaces[.destination],
              context.routePath.count >= 2
        else {
            return nil
        }

        var waypoints: [CourseRegistrationSubmissionWaypoint] = [
            .init(
                kind: .start,
                latitude: start.coordinate.latitude,
                longitude: start.coordinate.longitude,
                name: start.name
            )
        ]
        for waypoint in context.waypoints {
            guard let place = context.selectedPlaces[.waypoint(waypoint.id)] else { continue }
            waypoints.append(.init(
                kind: .via,
                latitude: place.coordinate.latitude,
                longitude: place.coordinate.longitude,
                name: place.name
            ))
        }
        waypoints.append(.init(
            kind: .destination,
            latitude: destination.coordinate.latitude,
            longitude: destination.coordinate.longitude,
            name: destination.name
        ))

        let distanceMeters = distanceMeters(for: context.routePath)
        guard distanceMeters > 0 else { return nil }
        return .init(
            name: start.name,
            address: start.name,
            distanceMeters: distanceMeters,
            waypoints: waypoints,
            practiceTypes: draft.selectedPracticeTypeCodes,
            description: trimmed(draft.description),
            caution: trimmed(draft.caution)
        )
    }

    private func distanceMeters(for path: [RodiCoordinate]) -> Int {
        guard path.count >= 2 else { return 0 }
        let distance = zip(path, path.dropFirst()).reduce(0.0) { partial, pair in
            partial + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }
        return max(0, Int(distance.rounded()))
    }

    private func showAlert(_ message: String, state: inout State) {
        state.alertToastRevision += 1
        state.alertToast = .init(message: message, revision: state.alertToastRevision)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CourseRegistrationDetailsLoadState: Equatable {
    case idle
    case loading
    case loaded(CourseRegistrationForm)
    case failed
}

struct CourseRegistrationDetailsDraft: Equatable {
    var selectedCategoryCodes: Set<String> = []
    var selectedPracticeTypeCodes: [String] = []
    var caution = ""
    var description = ""

    var isDirty: Bool {
        !selectedCategoryCodes.isEmpty
            || !selectedPracticeTypeCodes.isEmpty
            || !caution.isEmpty
            || !description.isEmpty
    }
}

struct CourseRegistrationAlertToastState: Equatable {
    let message: String
    let revision: Int
}

private enum CourseRegistrationDetailsTextLimit {
    static let caution = 100
    static let description = 30
}
