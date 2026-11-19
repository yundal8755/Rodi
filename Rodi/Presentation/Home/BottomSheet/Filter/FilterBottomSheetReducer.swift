//
//  FilterBottomSheetReducer.swift
//  Rodi
//

import Foundation

struct FilterBottomSheetReducer: Reducer {
    struct State {
        var appliedSelection: HomePracticeFilterSelection
        var draftSelection: HomePracticeFilterSelection
        var isApplying = false
        var isPresented = false

        init(filterStore: HomePracticeFilterStore = .init()) {
            let selection = filterStore.load()
            appliedSelection = selection
            draftSelection = selection
        }

        var canApply: Bool {
            !isApplying && draftSelection.filterTags != appliedSelection.filterTags
        }
    }

    enum Action {
        case present
        case dismiss
        case selectCategory(HomePracticeCategory)
        case toggleType(PlacePracticeType)
        case selectAll
        case reset
        case resetForNationwideBrowse
        case apply
        case applied(HomePracticeFilterSelection, browseNationwide: Bool)
        case authenticationRequired
        case failed(String)
        case delegate(Delegate)
    }

    enum Delegate {
        case applied(browseNationwide: Bool)
        case dismissed
        case requestAuthentication
        case showSnackbar(String)
    }

    private let memberRepository: MemberRepository
    private let filterStore: HomePracticeFilterStore
    private let hasActiveSession: () -> Bool
    private let onDelegate: (Delegate) -> Void

    init(
        memberRepository: MemberRepository,
        filterStore: HomePracticeFilterStore = .init(),
        hasActiveSession: @escaping () -> Bool,
        onDelegate: @escaping (Delegate) -> Void = { _ in }
    ) {
        self.memberRepository = memberRepository
        self.filterStore = filterStore
        self.hasActiveSession = hasActiveSession
        self.onDelegate = onDelegate
    }
}


// MARK: - Core Logics
extension FilterBottomSheetReducer {

    func reduce(_ state: inout State, with action: Action) -> Effect<Action> {
        switch action {
        case .present:
            guard hasActiveSession() else { return .send(.delegate(.requestAuthentication)) }
            state.draftSelection = state.appliedSelection
            state.isPresented = true
            RodiAnalytics.track(.practiceFilterOpened(presentation: "bottom_sheet"))

        case .dismiss:
            guard !state.isApplying else { return .none }
            state.isPresented = false
            state.draftSelection = state.appliedSelection
            return .send(.delegate(.dismissed))

        case .selectCategory(let category):
            guard !state.isApplying else { return .none }
            state.draftSelection.selectCategory(category)

        case .toggleType(let type):
            guard !state.isApplying else { return .none }
            state.draftSelection.toggleType(type)

        case .selectAll:
            guard !state.isApplying else { return .none }
            state.draftSelection.selectAll()

        case .reset, .resetForNationwideBrowse:
            guard !state.isApplying else { return .none }
            guard hasActiveSession() else { return .send(.delegate(.requestAuthentication)) }
            state.isApplying = true
            RodiAnalytics.track(.practiceFilterReset)
            if case .resetForNationwideBrowse = action {
                return updateFilterEffect(selection: .default, browseNationwide: true)
            }
            return updateFilterEffect(selection: .default)

        case .apply:
            guard state.canApply else { return .none }
            state.isApplying = true
            return updateFilterEffect(selection: state.draftSelection)

        case let .applied(selection, browseNationwide):
            state.appliedSelection = selection
            state.draftSelection = selection
            state.isApplying = false
            filterStore.save(selection)
            RodiAnalytics.track(.practiceFilterApplied(category: selection.category?.rawValue ?? "none", selectedTagCount: selection.filterTags.count, isAll: selection.isAllSelected))
            return .send(.delegate(.applied(browseNationwide: browseNationwide)))

        case .authenticationRequired:
            state.isApplying = false
            return .send(.delegate(.requestAuthentication))

        case .failed(let message):
            state.isApplying = false
            return .send(.delegate(.showSnackbar(message)))

        case .delegate(let delegate):
            onDelegate(delegate)
        }

        return .none
    }

    private func updateFilterEffect(selection: HomePracticeFilterSelection, browseNationwide: Bool = false) -> Effect<Action> {
        let repository = memberRepository
        return .run { send in
            do {
                try await repository.updatePlaceFilterTags(selection.filterTags)
                guard !Task.isCancelled else { return }
                await send(.applied(selection, browseNationwide: browseNationwide))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if requiresAuthentication(error) {
                    await send(.authenticationRequired)
                } else {
                    await send(.failed("필터를 적용하지 못했어요. 다시 시도해 주세요."))
                }
            }
        }
        .cancelTask(id: BottomSheetEffectID.practiceFilterUpdating)
    }

    private func requiresAuthentication(_ error: Error) -> Bool {
        guard let networkError = error as? NetworkError else { return false }
        return switch networkError {
        case .refreshFailGoRoot, .httpStatusCode(401): true
        case .apiError(let code, _, _): code.hasPrefix("AUTH_401") || code == "AUTH_400_1"
        default: false
        }
    }
}
