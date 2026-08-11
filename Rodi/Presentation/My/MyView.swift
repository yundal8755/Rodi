//
//  MyView.swift
//  Rodi
//

import Clarity
import SwiftUI

struct MyView: View {
    @EnvironmentObject private var networkConnectionMonitor: NetworkConnectionMonitor
    @ObservedObject var coordinator: Coordinator<MyRoute>
    @StateObject private var store: StoreOf<MyReducer>

    let isMyTabSelected: Bool
    let navigate: (MainTabIntent) -> Void
    let onLogoutCompleted: () -> Void
    let onReviewTestRequested: () -> Void
    let onReviewRequested: (ReviewWriteRequest) -> Void
    private let memberRepository: MemberRepository
    private let placeRepository: PlaceRepository
    private let practiceRepository: PracticeRepository
    private let reviewRepository: ReviewRepository
    private var router: Router<MyRoute> { coordinator.router }

    init(
        coordinator: Coordinator<MyRoute>,
        isMyTabSelected: Bool,
        navigate: @escaping (MainTabIntent) -> Void,
        onLogoutCompleted: @escaping () -> Void,
        onReviewTestRequested: @escaping () -> Void,
        onReviewRequested: @escaping (ReviewWriteRequest) -> Void,
        dependencies: AppDependencies
    ) {
        self.coordinator = coordinator
        self.isMyTabSelected = isMyTabSelected
        self.navigate = navigate
        self.onLogoutCompleted = onLogoutCompleted
        self.onReviewTestRequested = onReviewTestRequested
        self.onReviewRequested = onReviewRequested
        _store = StateObject(
            wrappedValue: Store(
                state: MyReducer.State(),
                reducer: MyReducer(
                    authRepository: dependencies.authRepository,
                    memberRepository: dependencies.memberRepository,
                    practiceRepository: dependencies.practiceRepository,
                    recentLoginProviderStore: dependencies.recentLoginProviderStore
                )
            )
        )
        memberRepository = dependencies.memberRepository
        placeRepository = dependencies.placeRepository
        practiceRepository = dependencies.practiceRepository
        reviewRepository = dependencies.reviewRepository
    }

    var body: some View {
        NavigationStack(path: coordinator.pathBinding) {
            MyProfileView(
                profile: store.state.profile,
                isLoading: store.state.isLoadingProfile,
                hasCompletedInitialLoad: store.state.hasCompletedInitialLoad,
                errorMessage: store.state.profileErrorMessage,
                openSettings: { router.push(.settings) },
                openDrivingGoal: { router.push(.drivingGoal) },
                openSavedPlaces: { router.push(.savedPlaces) },
                openPracticeRecords: { router.push(.practiceRecords) },
                openMyPosts: { router.push(.myPosts) },
                retry: { store.send(.retryProfileTapped) },
                practiceRecords: store.state.practiceRecordPreview,
                isLoadingPracticeRecords: store.state.isLoadingPracticeRecords,
                hasCompletedPracticeRecordLoad: store.state.hasCompletedPracticeRecordLoad,
                practiceRecordErrorMessage: store.state.practiceRecordErrorMessage,
                retryPracticeRecords: { store.send(.retryPracticeRecordsTapped) },
                reviewRequested: onReviewRequested,
                reviewTestAction: onReviewTestRequested
            )
            .navigationDestination(for: MyRoute.self) { route in
                    destinationView(for: route)
                    .background(MyInteractivePopGestureEnabler())
                    .myEdgeSwipeBack(
                        isTopRoute: coordinator.path.last == route,
                        router: router
                    )
            }
        }
        .rodiSnackbar(message: store.state.snackbarMessage)
        .task(id: isMyTabSelected) {
            guard isMyTabSelected else { return }
            store.send(.networkStatusChanged(networkConnectionMonitor.status))
            store.send(.appeared)
            store.send(.practiceRecordsAppeared)
        }
        .onChange(of: networkConnectionMonitor.status) { status in
            guard isMyTabSelected else { return }
            store.send(.networkStatusChanged(status))
        }
        .onChange(of: store.state.didEndSessionRequestID) { requestID in
            guard requestID > 0 else { return }
            router.popToRoot()
            onLogoutCompleted()
        }
        .clarityMask()
    }

}

// MARK: Layout
private extension MyView {

    @ViewBuilder
    private func destinationView(for route: MyRoute) -> some View {
        switch route {
        case .settings:
            MySettingsView(backAction: { router.pop() }, navigate: router.push)
            
        case .drivingGoal:
            MyDrivingGoalView(
                initialDrivingGoal: "",
                memberRepository: memberRepository,
                onUpdated: { store.send(.drivingGoalUpdated($0)) },
                backAction: { router.pop() }
            )
            
        case .savedPlaces:
            SavedPlacesView(
                placeRepository: placeRepository,
                backAction: { router.pop() },
                selectPlaceAction: { item in
                    RodiAnalytics.track(.savedPlaceSelected)
                    router.popToRoot()
                    navigate(.openHomePlace(item))
                }
            )

        case .practiceRecords:
            MyPracticeRecordsView(
                practiceRepository: practiceRepository,
                reviewRequested: onReviewRequested,
                backAction: { router.pop() }
            )

        case .myPosts:
            MyPostsPlaceholderView(backAction: { router.pop() })
            
        case .permissions:
            MyPermissionSettingsView(backAction: { router.pop() })
            
        case .terms:
            MyTermsView(backAction: { router.pop() }, navigate: router.push)
            
        case .licenses:
            MyOpenSourceLicenseView(backAction: { router.pop() })
            
        case .accountManagement:
            MyAccountManagementView(
                backAction: { router.pop() },
                navigate: router.push,
                logoutAction: { store.send(.logoutConfirmed) },
                withdrawalAction: { store.send(.withdrawalConfirmed) }
            )
            
        case .contact:
            MyContactView(backAction: { router.pop() })
            
        case .legalDocument(let document):
            MyLegalDocumentView(document: document, backAction: { router.pop() })
        }
    }
}
