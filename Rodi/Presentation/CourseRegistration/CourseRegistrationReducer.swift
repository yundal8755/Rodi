import Foundation

@MainActor
struct CourseRegistrationReducer: Reducer {
    struct State: Equatable {
        enum Route: Equatable {
            case tutorial
            case registration
            case registrationSearch(CourseRegistrationInputTarget)
            case pinEditing
            case pinEditSearch
            case details
        }

        var route: Route
        var tutorial = CourseRegistrationTutorialReducer.State()
        var mapSelection: CourseRegistrationMapSelectionReducer.State
        var errorMessage: String?
        var tutorialCompletionRevision = 0
        var pinEditing: CourseRegistrationPinEditingReducer.State?
        var details = CourseRegistrationDetailsReducer.State()
        var isRegistrationDiscardConfirmationPresented = false
        var courseRegistrationCompletionRevision = 0
        var courseRegistrationExitRevision = 0

        init(isCourseTutorialCompleted: Bool) {
            route = isCourseTutorialCompleted ? .registration : .tutorial
            mapSelection = .init(isCourseTutorialCompleted: isCourseTutorialCompleted)
        }
    }

    enum Action {
        case tutorial(CourseRegistrationTutorialReducer.Action)
        case mapSelection(CourseRegistrationMapSelectionReducer.Action)
        case errorDismissed

        case registrationCloseTapped
        case registrationDiscardConfirmed
        case registrationDiscardCancelled

        case details(CourseRegistrationDetailsReducer.Action)
        case registrationSearchDismissed
        case registrationSearchResultSelected(CourseRegistrationPlaceSearchItem)
        case pinEditing(CourseRegistrationPinEditingReducer.Action)
        case pinEditSearchDismissed
        case pinEditSearchResultSelected(CourseRegistrationPlaceSearchItem)
    }

    private let tutorialReducer: CourseRegistrationTutorialReducer
    private let mapSelectionReducer: CourseRegistrationMapSelectionReducer
    private let pinEditingReducer: CourseRegistrationPinEditingReducer
    private let detailsReducer: CourseRegistrationDetailsReducer

    init(
        memberRepository: MemberRepository,
        courseRepository: CourseRepository,
        mapService: CourseRegistrationMapService? = nil,
        directionsService: KakaoDirectionsService = .init()
    ) {
        tutorialReducer = .init(memberRepository: memberRepository)
        let resolvedMapService = mapService ?? CourseRegistrationMapService()
        mapSelectionReducer = .init(mapService: resolvedMapService, directionsService: directionsService)
        pinEditingReducer = .init(mapService: resolvedMapService, directionsService: directionsService)
        detailsReducer = .init(courseRepository: courseRepository)
    }

    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .tutorial(let childAction):
            if case .delegate(let delegate) = childAction {
                return reduceTutorialDelegate(delegate, state: &state)
            }
            guard state.route == .tutorial else { return .none }
            return tutorialReducer
                .reduce(&state.tutorial, with: childAction)
                .map(Action.tutorial)

        case .errorDismissed:
            state.errorMessage = nil

        case .mapSelection(let childAction):
            if case .delegate(let delegate) = childAction {
                return reduceMapSelectionDelegate(delegate, state: &state)
            }
            guard state.route == .registration else { return .none }
            return mapSelectionReducer
                .reduce(&state.mapSelection, with: childAction)
                .map(Action.mapSelection)

        case .registrationCloseTapped:
            guard state.route == .registration else { return .none }
            return mapSelectionReducer
                .reduce(&state.mapSelection, with: .closeTapped)
                .map(Action.mapSelection)

        case .registrationDiscardConfirmed:
            guard state.isRegistrationDiscardConfirmationPresented else { return .none }
            state.isRegistrationDiscardConfirmationPresented = false
            state.courseRegistrationExitRevision += 1
            state.pinEditing = nil
            state.details = .init()
            return mapSelectionReducer
                .reduce(&state.mapSelection, with: .reset)
                .map(Action.mapSelection)

        case .registrationDiscardCancelled:
            state.isRegistrationDiscardConfirmationPresented = false

        case .details(let childAction):
            if case .delegate(let delegate) = childAction {
                return reduceDetailsDelegate(delegate, state: &state)
            }
            guard state.route == .details else { return .none }
            return detailsReducer
                .reduce(&state.details, with: childAction)
                .map(Action.details)

        case .registrationSearchDismissed:
            guard case .registrationSearch = state.route else { return .none }
            state.route = .registration

        case .registrationSearchResultSelected(let result):
            guard case let .registrationSearch(target) = state.route else { return .none }
            state.route = .registration
            return mapSelectionReducer
                .reduce(&state.mapSelection, with: .searchResultSelected(target, result))
                .map(Action.mapSelection)

        case .pinEditing(let childAction):
            if case .delegate(let delegate) = childAction {
                return reducePinEditingDelegate(delegate, state: &state)
            }
            guard state.route == .pinEditing || state.route == .pinEditSearch,
                  state.pinEditing != nil
            else {
                return .none
            }
            return pinEditingReducer
                .reduce(&state.pinEditing!, with: childAction)
                .map(Action.pinEditing)

        case .pinEditSearchDismissed:
            guard state.route == .pinEditSearch, state.pinEditing != nil else { return .none }
            state.route = .pinEditing

        case .pinEditSearchResultSelected(let result):
            guard state.route == .pinEditSearch, state.pinEditing != nil else { return .none }
            state.route = .pinEditing
            return pinEditingReducer
                .reduce(&state.pinEditing!, with: .searchResultSelected(result))
                .map(Action.pinEditing)
        }
        return .none
    }

    private func reduceDetailsDelegate(
        _ delegate: CourseRegistrationDetailsReducer.Delegate,
        state: inout State
    ) -> Effect<Action> {
        switch delegate {
        case .backRequested:
            guard state.route == .details else { return .none }
            state.route = .registration
            return .none

        case .completionConfirmed:
            guard state.route == .details else { return .none }
            state.courseRegistrationCompletionRevision += 1
            return .none
        }
    }

    private func reduceTutorialDelegate(
        _ delegate: CourseRegistrationTutorialReducer.Delegate,
        state: inout State
    ) -> Effect<Action> {
        switch delegate {
        case .completed:
            guard state.route == .tutorial else { return .none }
            state.route = .registration
            state.tutorialCompletionRevision += 1
            return mapSelectionReducer
                .reduce(&state.mapSelection, with: .prepareStartSelection)
                .map(Action.mapSelection)
        }
    }

    private func reduceMapSelectionDelegate(
        _ delegate: CourseRegistrationMapSelectionReducer.Delegate,
        state: inout State
    ) -> Effect<Action> {
        switch delegate {
        case .openSearch(let target):
            guard state.route == .registration else { return .none }
            state.route = .registrationSearch(target)
            return .none

        case .openPinEdit(let target, let originalPlace):
            guard state.route == .registration else { return .none }
            state.pinEditing = .init(target: target, originalPlace: originalPlace)
            state.route = .pinEditing
            return .none

        case .openDetails(let context):
            guard state.route == .registration else { return .none }
            state.route = .details
            return detailsReducer
                .reduce(&state.details, with: .start(context))
                .map(Action.details)

        case .closeRequested(let hasInput):
            guard state.route == .registration else { return .none }
            if hasInput {
                state.isRegistrationDiscardConfirmationPresented = true
            } else {
                state.courseRegistrationExitRevision += 1
            }
            return .none

        case .showError(let message):
            state.errorMessage = message
            return .none
        }
    }

    private func reducePinEditingDelegate(
        _ delegate: CourseRegistrationPinEditingReducer.Delegate,
        state: inout State
    ) -> Effect<Action> {
        switch delegate {
        case .openSearch:
            guard state.route == .pinEditing else { return .none }
            state.route = .pinEditSearch
            return .none

        case .cancelled:
            guard state.route == .pinEditing || state.route == .pinEditSearch else { return .none }
            state.pinEditing = nil
            state.route = .registration
            return .none

        case .completed(let target, let replacement, let routePath):
            guard state.route == .pinEditing else { return .none }
            state.pinEditing = nil
            state.route = .registration
            return mapSelectionReducer
                .reduce(&state.mapSelection, with: .pinEditApplied(target, replacement, routePath))
                .map(Action.mapSelection)

        case .showError(let message):
            state.errorMessage = message
            return .none
        }
    }
}
