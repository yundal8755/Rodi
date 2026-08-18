//
//  MyPostsView.swift
//  Rodi
//

import SwiftUI

struct MyPostsView: View {
    @StateObject private var store: StoreOf<MyPostsReducer>
    @State private var activeMenuReviewID: Int?
    @State private var activeMenuCourseID: Int64?
    @State private var isCourseFilterExpanded = false

    let backAction: () -> Void
    let openPracticeRecords: () -> Void
    let openCourseRegistration: () -> Void
    let practiceRecordsRefreshRequested: () -> Void
    let reviewFlowFinishedRequestID: Int
    let editRequested: (Int) -> Void

    init(
        reviewRepository: ReviewRepository,
        practiceRepository: PracticeRepository,
        courseRepository: CourseRepository,
        backAction: @escaping () -> Void,
        openPracticeRecords: @escaping () -> Void,
        openCourseRegistration: @escaping () -> Void,
        practiceRecordsRefreshRequested: @escaping () -> Void,
        reviewFlowFinishedRequestID: Int,
        editRequested: @escaping (Int) -> Void
    ) {
        _store = StateObject(
            wrappedValue: Store(
                state: MyPostsReducer.State(),
                reducer: MyPostsReducer(
                    reviewRepository: reviewRepository,
                    practiceRepository: practiceRepository,
                    courseRepository: courseRepository
                )
            )
        )
        self.backAction = backAction
        self.openPracticeRecords = openPracticeRecords
        self.openCourseRegistration = openCourseRegistration
        self.practiceRecordsRefreshRequested = practiceRecordsRefreshRequested
        self.reviewFlowFinishedRequestID = reviewFlowFinishedRequestID
        self.editRequested = editRequested
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                MySubpageHeader(title: "내 활동", backAction: backAction)
                tabBar
                content
            }

            if store.state.deleteTargetReviewID != nil {
                reviewDeleteConfirmationDialog
                    .zIndex(20)
            }

            if store.state.deleteTargetCourseID != nil {
                courseDeleteConfirmationDialog
                    .zIndex(20)
            }
        }
        .background(RodiColor.white)
        .toolbar(.hidden, for: .navigationBar)
        .overlayPreferenceValue(RodiDropdownAnchorPreferenceKey.self) { anchors in
            dropdownOverlay(anchors: anchors)
        }
        .rodiSnackbar(message: store.state.snackbarMessage)
        .onAppear {
            store.send(.appeared)
        }
        .onChange(of: reviewFlowFinishedRequestID) { requestID in
            guard requestID > 0 else { return }
            store.send(.reloadReviewsRequested)
        }
        .onChange(of: store.state.practiceRecordsRefreshRequestID) { requestID in
            guard requestID > 0 else { return }
            practiceRecordsRefreshRequested()
        }
        .onChange(of: store.state.pendingEditReviewID) { reviewID in
            guard let reviewID else { return }
            editRequested(reviewID)
            store.send(.editRequestHandled(reviewID: reviewID))
        }
    }
}

// MARK: - Layout
private extension MyPostsView {

    var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "등록한 코스", tab: .courses)
            tabButton(title: "작성한 후기", tab: .reviews)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RodiColor.gray200)
                .frame(height: 1)
        }
    }

    func tabButton(title: String, tab: MyPostsReducer.Tab) -> some View {
        let isSelected = store.state.selectedTab == tab

        return Button {
            closeDropdowns()
            store.send(.tabSelected(tab))
        } label:{
            Text(title)
                .font(.pretendard(size: 16, weight: isSelected ? .semibold : .medium))
                .tracking(-0.32)
                .foregroundStyle(isSelected ? RodiColor.black : RodiColor.gray400)
                .frame(maxWidth: .infinity)
                .frame(height: 45)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isSelected ? RodiColor.black : .clear)
                        .frame(height: 2)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    var content: some View {
        switch store.state.selectedTab {
        case .courses:
            courseContent
        case .reviews:
            reviewContent
        }
    }

    var courseContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                courseFilterButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if store.state.isCourseInitialLoading, store.state.courseItems.isEmpty {
                ProgressView()
                    .tint(RodiColor.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.state.courseItems.isEmpty {
                MyCoursesEmptyState(
                    filter: store.state.selectedCourseFilter,
                    errorMessage: store.state.courseErrorMessage,
                    retry: { store.send(.retryTapped) },
                    openCourseRegistration: openCourseRegistration
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(store.state.courseItems) { course in
                            VStack(alignment: .leading, spacing: 24) {
                                MyCourseRow(
                                    course: course,
                                    isMenuExpanded: activeMenuCourseID == course.id,
                                    menuTapped: { toggleMenu(for: course.id) }
                                )

                                Rectangle()
                                    .fill(RodiColor.primaryMinus100)
                                    .frame(height: 1)
                            }
                        }

                        coursePaginationFooter
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    var courseFilterButton: some View {
        Button {
            activeMenuCourseID = nil
            activeMenuReviewID = nil
            isCourseFilterExpanded.toggle()
        } label: {
            HStack(spacing: 2) {
                Text(isCourseFilterExpanded ? "접기" : store.state.selectedCourseFilter.title)
                    .rodiTypography(.body3Medium)

                Image("ic_chevron_down")
                    .resizable()
                    .scaledToFit()
                    .rotationEffect(.degrees(isCourseFilterExpanded ? 180 : 0))
                    .frame(width: 16, height: 16)
            }
            .foregroundStyle(RodiColor.gray700)
            .frame(minWidth: 44, minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCourseFilterExpanded ? "코스 상태 필터 닫기" : "코스 상태 필터 열기")
        .anchorPreference(key: RodiDropdownAnchorPreferenceKey.self, value: .bounds) {
            [AnyHashable("course-filter"): $0]
        }
    }

    @ViewBuilder
    var coursePaginationFooter: some View {
        if store.state.isCourseNextPageLoading {
            ProgressView()
                .tint(RodiColor.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else if let lastItem = store.state.courseItems.last,
                  store.state.hasNextCoursePage,
                  store.state.courseErrorMessage == nil {
            Color.clear
                .frame(height: 1)
                .onAppear {
                    store.send(.courseLastItemAppeared(lastItem))
                }
        }

        if let errorMessage = store.state.courseErrorMessage, !store.state.courseItems.isEmpty {
            MyPostsRetryFooter(message: errorMessage, retry: { store.send(.retryTapped) })
        }
    }

    @ViewBuilder
    var reviewContent: some View {
        if store.state.isInitialLoading, store.state.items.isEmpty {
            ProgressView()
                .tint(RodiColor.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.state.items.isEmpty {
            MyPostsEmptyState(
                errorMessage: store.state.errorMessage,
                retry: { store.send(.retryTapped) },
                openPracticeRecords: openPracticeRecords,
                hasPracticeRecords: store.state.hasPracticeRecords
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(store.state.items) { review in
                        VStack(alignment: .leading, spacing: 24) {
                            MyPostReviewRow(
                                review: review,
                                isMenuExpanded: activeMenuReviewID == review.id,
                                menuTapped: { toggleMenu(for: review.id) }
                            )

                            Rectangle()
                                .fill(RodiColor.primaryMinus100)
                                .frame(height: 1)
                        }
                    }

                    reviewPaginationFooter
                }
                .padding(.horizontal, 16)
                .padding(.top, 25)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    var reviewPaginationFooter: some View {
        if store.state.isNextPageLoading {
            ProgressView()
                .tint(RodiColor.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else if let lastItem = store.state.items.last,
                  store.state.hasNextPage,
                  store.state.errorMessage == nil {
            Color.clear
                .frame(height: 1)
                .onAppear {
                    store.send(.lastItemAppeared(lastItem))
                }
        }

        if let errorMessage = store.state.errorMessage, !store.state.items.isEmpty {
            MyPostsRetryFooter(message: errorMessage, retry: { store.send(.retryTapped) })
        }
    }

    @ViewBuilder
    func dropdownOverlay(
        anchors: [AnyHashable: Anchor<CGRect>]
    ) -> some View {
        if isCourseFilterExpanded,
           let anchor = anchors[AnyHashable("course-filter")] {
            menuOverlay(anchor: anchor) {
                RodiDropdownMenu(
                    options: MyPostsReducer.CourseFilter.allCases
                        .filter { $0 != store.state.selectedCourseFilter }
                        .map {
                        .init(id: $0.title, title: $0.title)
                        },
                    onSelect: { option in
                        guard let filter = MyPostsReducer.CourseFilter.allCases.first(where: { $0.title == option.id }) else {
                            return
                        }
                        isCourseFilterExpanded = false
                        store.send(.courseFilterSelected(filter))
                    }
                )
            }
        } else if let courseID = activeMenuCourseID,
                  let anchor = anchors[AnyHashable("course-\(courseID)")] {
            menuOverlay(anchor: anchor) {
                RodiDropdownMenu(
                    options: [.init(id: "delete", title: "삭제하기")],
                    onSelect: { _ in
                        activeMenuCourseID = nil
                        store.send(.deleteCourseRequested(courseID: courseID))
                    }
                )
            }
        } else if let reviewID = activeMenuReviewID,
                  let anchor = anchors[AnyHashable("review-\(reviewID)")] {
            menuOverlay(anchor: anchor) {
                RodiDropdownMenu(
                    options: [
                        .init(id: "edit", title: "수정하기"),
                        .init(id: "delete", title: "삭제하기")
                    ],
                    onSelect: { option in
                        activeMenuReviewID = nil
                        if option.id == "edit" {
                            store.send(.editRequested(reviewID: reviewID))
                        } else {
                            store.send(.deleteRequested(reviewID: reviewID))
                        }
                    }
                )
            }
        }
    }

    func menuOverlay<Menu: View>(
        anchor: Anchor<CGRect>,
        @ViewBuilder menu: @escaping () -> Menu
    ) -> some View {
        GeometryReader { proxy in
            let triggerFrame = proxy[anchor]

            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { closeDropdowns() }

                menu()
                    .alignmentGuide(.leading) { dimensions in
                        dimensions[.trailing] - triggerFrame.maxX
                    }
                    .alignmentGuide(.top) { dimensions in
                        dimensions[.top] - triggerFrame.maxY - 4
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .zIndex(10)
    }

    func toggleMenu(for reviewID: Int) {
        activeMenuCourseID = nil
        isCourseFilterExpanded = false
        activeMenuReviewID = activeMenuReviewID == reviewID ? nil : reviewID
    }

    func toggleMenu(for courseID: Int64) {
        activeMenuReviewID = nil
        isCourseFilterExpanded = false
        activeMenuCourseID = activeMenuCourseID == courseID ? nil : courseID
    }

    func closeDropdowns() {
        activeMenuReviewID = nil
        activeMenuCourseID = nil
        isCourseFilterExpanded = false
    }

    var reviewDeleteConfirmationDialog: some View {
        ReviewDeleteConfirmationDialog(
            isDeleting: store.state.isDeleting,
            errorMessage: store.state.deleteErrorMessage,
            deleteAction: { store.send(.deleteConfirmed) },
            cancelAction: { store.send(.deleteCancelled) }
        )
    }

    var courseDeleteConfirmationDialog: some View {
        CourseDeleteConfirmationDialog(
            isDeleting: store.state.isDeletingCourse,
            errorMessage: store.state.courseDeleteErrorMessage,
            deleteAction: { store.send(.deleteCourseConfirmed) },
            cancelAction: { store.send(.deleteCourseCancelled) }
        )
    }
}
