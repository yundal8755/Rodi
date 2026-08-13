//
//  KakaoLocalSearchTestView.swift
//  Rodi
//

import SwiftUI

struct KakaoLocalSearchTestRootView: View {
    @StateObject private var store = Store(
        state: KakaoLocalSearchTestReducer.State(),
        reducer: KakaoLocalSearchTestReducer()
    )

    var body: some View {
        KakaoLocalSearchTestView(
            state: store.state,
            send: store.send
        )
    }
}

private struct KakaoLocalSearchTestView: View {
    let state: KakaoLocalSearchTestReducer.State
    let send: (KakaoLocalSearchTestReducer.Action) -> Void

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            searchResults
        }
        .background(RodiColor.white.ignoresSafeArea())
        .onAppear {
            send(.appeared)
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
    }
}

// MARK: - Layout
private extension KakaoLocalSearchTestView {
    var searchField: some View {
        HomeSearchTextField(
            text: Binding(
                get: { state.query },
                set: { send(.queryChanged($0)) }
            ),
            isFocused: $isSearchFieldFocused,
            backAction: clearSearch,
            submitAction: {
                isSearchFieldFocused = false
                send(.searchTapped)
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(RodiColor.white)
    }

    var searchResults: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                regionResults

                if !state.regions.isEmpty, showsPlaceSection {
                    RodiColor.primaryMinus100
                        .frame(height: 4)
                }

                placeResults
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture {
            isSearchFieldFocused = false
        }
    }

    var regionResults: some View {
        ForEach(state.regions) { region in
            Button {
                isSearchFieldFocused = false
                send(.regionTapped(region))
            } label: {
                resultRow(
                    title: region.displayName,
                    imageName: "ic_search",
                    accessibilityLabel: "\(region.displayName) 검색"
                )
            }
            .buttonStyle(.plain)

            if region.id != state.regions.last?.id {
                Divider()
                    .overlay(RodiColor.primaryMinus100)
            }
        }
    }

    @ViewBuilder
    var placeResults: some View {
        if state.query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            EmptyView()
        } else if state.isPlaceLoading {
            ProgressView()
                .tint(RodiColor.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else if let errorMessage = state.placeErrorMessage {
            VStack(spacing: 12) {
                messageState(errorMessage)

                Button {
                    send(.searchTapped)
                } label: {
                    Text("다시 시도")
                        .rodiTypography(.buttonMedium)
                        .foregroundStyle(RodiColor.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 24)
        } else if state.hasSearchedPlaces, state.places.isEmpty, state.regions.isEmpty {
            messageState("검색 결과가 없어요.")
        } else {
            ForEach(state.places) { place in
                resultRow(
                    title: place.title,
                    imageName: "ic_map_pin",
                    accessibilityLabel: "\(place.title) 장소"
                )

                Divider()
                    .overlay(RodiColor.primaryMinus100)
            }
        }
    }

    var showsPlaceSection: Bool {
        state.isPlaceLoading ||
            state.placeErrorMessage != nil ||
            !state.places.isEmpty
    }

    func resultRow(
        title: String,
        imageName: String,
        accessibilityLabel: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(imageName)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(RodiColor.gray600)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            Text(title)
                .rodiTypography(.body1Medium)
                .foregroundStyle(RodiColor.gray800)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    func messageState(_ message: String) -> some View {
        Text(message)
            .rodiTypography(.body3Medium)
            .foregroundStyle(RodiColor.gray600)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
    }

    func clearSearch() {
        isSearchFieldFocused = true
        send(.queryChanged(""))
    }
}
