//
//  MyPostsView.swift
//  Rodi
//

import SwiftUI

struct MyPostsView: View {
    @StateObject private var store: StoreOf<MyPostsReducer>
    @State private var activeMenuReviewID: Int?

    let backAction: () -> Void
    let openPracticeRecords: () -> Void
    let practiceRecordsRefreshRequested: () -> Void
    let reviewFlowFinishedRequestID: Int
    let editRequested: (Int) -> Void

    init(
        reviewRepository: ReviewRepository,
        practiceRepository: PracticeRepository,
        backAction: @escaping () -> Void,
        openPracticeRecords: @escaping () -> Void,
        practiceRecordsRefreshRequested: @escaping () -> Void,
        reviewFlowFinishedRequestID: Int,
        editRequested: @escaping (Int) -> Void
    ) {
        _store = StateObject(
            wrappedValue: Store(
                state: MyPostsReducer.State(),
                reducer: MyPostsReducer(
                    reviewRepository: reviewRepository,
                    practiceRepository: practiceRepository
                )
            )
        )
        self.backAction = backAction
        self.openPracticeRecords = openPracticeRecords
        self.practiceRecordsRefreshRequested = practiceRecordsRefreshRequested
        self.reviewFlowFinishedRequestID = reviewFlowFinishedRequestID
        self.editRequested = editRequested
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                MySubpageHeader(title: "내 게시글", backAction: backAction)
                content
            }

            if let reviewID = store.state.deleteTargetReviewID {
                deleteConfirmationDialog(reviewID: reviewID)
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
            store.send(.reloadRequested)
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

    @ViewBuilder
    var content: some View {
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

                    paginationFooter
                }
                .padding(.horizontal, 16)
                .padding(.top, 25)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    var paginationFooter: some View {
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
            VStack(spacing: 8) {
                Text(errorMessage)
                    .rodiTypography(.body3Medium)
                    .foregroundStyle(RodiColor.gray600)

                Button {
                    store.send(.retryTapped)
                } label: {
                    Text("다시 시도")
                        .rodiTypography(.body3Medium)
                        .foregroundStyle(RodiColor.primary)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    func dropdownOverlay(
        anchors: [AnyHashable: Anchor<CGRect>]
    ) -> some View {
        if let reviewID = activeMenuReviewID,
           let anchor = anchors[AnyHashable(reviewID)] {
            GeometryReader { proxy in
                let triggerFrame = proxy[anchor]

                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            activeMenuReviewID = nil
                        }

                    RodiDropdownMenu(
                        options: [
                            .init(id: "edit", title: "수정하기"),
                            .init(id: "delete", title: "삭제하기")
                        ],
                        onSelect: { option in
                            activeMenuReviewID = nil
                            if option.id == "edit" {
                                store.send(.editRequested(reviewID: reviewID))
                            } else if option.id == "delete" {
                                store.send(.deleteRequested(reviewID: reviewID))
                            }
                        }
                    )
                    .alignmentGuide(.leading) { dimensions in
                        dimensions[.trailing] - triggerFrame.maxX
                    }
                    .alignmentGuide(.top) { dimensions in
                        dimensions[.top] - triggerFrame.maxY - 2.5
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea()
            .zIndex(10)
        }
    }

    func toggleMenu(for reviewID: Int) {
        activeMenuReviewID = activeMenuReviewID == reviewID ? nil : reviewID
    }

    func deleteConfirmationDialog(reviewID: Int) -> some View {
        ReviewDeleteConfirmationDialog(
            isDeleting: store.state.isDeleting,
            errorMessage: store.state.deleteErrorMessage,
            deleteAction: { store.send(.deleteConfirmed) },
            cancelAction: { store.send(.deleteCancelled) }
        )
    }
}

private struct MyPostReviewRow: View {
    let review: MyReviewItem
    let isMenuExpanded: Bool
    let menuTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(review.placeName)
                    .font(.pretendard(size: 15, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(RodiColor.black)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .trailing) {
                        Button(action: menuTapped) {
                            Image("ic_more_horizontal_circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel(isMenuExpanded ? "후기 메뉴 닫기" : "후기 메뉴 열기")
                        .anchorPreference(key: RodiDropdownAnchorPreferenceKey.self, value: .bounds) {
                            [AnyHashable(review.id): $0]
                        }
                    }

                Text(Self.dateFormatter.string(from: review.createdAt))
                    .font(.pretendard(size: 13, weight: .medium))
                    .tracking(-0.26)
                    .foregroundStyle(RodiColor.gray600)
            }

            Text(review.content)
                .font(.pretendard(size: 13, weight: .regular))
                .tracking(-0.26)
                .foregroundStyle(RodiColor.gray700)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 37)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(RodiColor.gray200, lineWidth: 1)
                }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yy.MM.dd"
        return formatter
    }()
}

private struct MyPostsEmptyState: View {
    let errorMessage: String?
    let retry: () -> Void
    let openPracticeRecords: () -> Void
    let hasPracticeRecords: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .rodiTypography(.body3Medium)
                    .foregroundStyle(RodiColor.gray600)

                Button(action: retry) {
                    Text("다시 시도")
                        .rodiTypography(.body3Medium)
                        .foregroundStyle(RodiColor.primary)
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .center) {
                    Image("ic_review")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .padding(.bottom, 16)

                    Text("아직 작성한 후기가 없어요!")
                        .rodiTypography(.headline1)
                        .foregroundStyle(RodiColor.gray600)
                        .padding(.bottom, 8)

                    Text("다녀온 코스의 경험을 기록해보세요.")
                        .rodiTypography(.body3Medium)
                        .foregroundStyle(RodiColor.gray600)

                    if hasPracticeRecords {
                        Button(action: openPracticeRecords) {
                            Text("연습기록 보러가기")
                                .rodiTypography(.body3Medium)
                                .foregroundStyle(RodiColor.primary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 7)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(RodiColor.primary, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 16)
                        .accessibilityLabel("연습기록 보러가기")
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 104)
    }
}
