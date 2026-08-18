import SwiftUI

private enum CourseRegistrationMapPinLayout {
    static let size: CGFloat = 34
    // The visible point of the 34pt pin asset is at y = 32.5pt.
    // Shift its center up so that point, not the asset center, matches the map center coordinate.
    static let centerAlignmentOffsetY: CGFloat = -15.5
}

struct CourseRegistrationView: View {
    @StateObject private var store: StoreOf<CourseRegistrationReducer>
    @State private var handledCompletionRevision = 0
    @State private var handledCourseRegistrationCompletionRevision = 0
    @State private var handledCourseRegistrationExitRevision = 0

    let closeAction: () -> Void
    let tutorialCompletedAction: () -> Void

    init(
        isCourseTutorialCompleted: Bool,
        memberRepository: MemberRepository,
        courseRepository: CourseRepository,
        closeAction: @escaping () -> Void,
        tutorialCompletedAction: @escaping () -> Void,
        courseRegistrationCompletedAction: @escaping () -> Void
    ) {
        self.closeAction = closeAction
        self.tutorialCompletedAction = tutorialCompletedAction
        _store = StateObject(wrappedValue: Store(
            state: .init(isCourseTutorialCompleted: isCourseTutorialCompleted),
            reducer: CourseRegistrationReducer(
                memberRepository: memberRepository,
                courseRepository: courseRepository
            )
        ))
        self.courseRegistrationCompletedAction = courseRegistrationCompletedAction
    }

    private let courseRegistrationCompletedAction: () -> Void

    var body: some View {
        Group {
            switch store.state.route {
            case .tutorial:
                CourseRegistrationTutorialView(
                    state: store.state.tutorial,
                    closeAction: closeAction,
                    send: { store.send(.tutorial($0)) }
                )
            case .registration:
                CourseRegistrationEntryView(
                    waypoints: store.state.mapSelection.waypoints,
                    selectedPlaces: store.state.mapSelection.selectedPlaces,
                    routePath: store.state.mapSelection.routePath,
                    isRouteLoading: store.state.mapSelection.isRouteLoading,
                    map: store.state.mapSelection.map,
                    closeAction: { store.send(.registrationCloseTapped) },
                    addWaypointAction: { store.send(.mapSelection(.waypointAddTapped)) },
                    removeWaypointAction: { store.send(.mapSelection(.waypointRemoveTapped($0))) },
                    inputTargetTappedAction: { store.send(.mapSelection(.inputTargetTapped($0))) },
                    currentLocationAction: { store.send(.mapSelection(.currentLocationTapped)) },
                    mapViewportChangedAction: { center, isUserInitiated in
                        store.send(.mapSelection(.viewportChanged(center, isUserInitiated: isUserInitiated)))
                    },
                    routePointTappedAction: { store.send(.mapSelection(.routePointTapped($0))) },
                    placeSelectionAction: { store.send(.mapSelection(.placeSelectionTapped)) },
                    selectionCompletionAction: { store.send(.mapSelection(.selectionCompletionTapped)) },
                    registrationCompletionAction: { store.send(.mapSelection(.registrationCompletionTapped)) }
                )
                .onAppear { store.send(.mapSelection(.appeared)) }
            case .registrationSearch:
                CourseRegistrationPlaceSearchView(
                    closeAction: { store.send(.registrationSearchDismissed) },
                    resultSelectedAction: { store.send(.registrationSearchResultSelected($0)) }
                )
            case .pinEditing:
                if let pinEdit = store.state.pinEditing {
                    CourseRegistrationPinEditView(
                        pinEdit: pinEdit,
                        waypoints: store.state.mapSelection.waypoints,
                        selectedPlaces: store.state.mapSelection.selectedPlaces,
                        mapViewportChangedAction: { center, isUserInitiated in
                            store.send(.pinEditing(.viewportChanged(center, isUserInitiated: isUserInitiated)))
                        },
                        currentLocationAction: { store.send(.pinEditing(.currentLocationTapped)) },
                        addressTappedAction: { store.send(.pinEditing(.addressTapped)) },
                        selectionAction: { store.send(.pinEditing(.selectionTapped)) },
                        retryAction: { store.send(.pinEditing(.retryTapped)) },
                        completionAction: { points in
                            store.send(.pinEditing(.completionTapped(points)))
                        },
                        backAction: { store.send(.pinEditing(.backTapped)) }
                    )
                }
            case .pinEditSearch:
                CourseRegistrationPlaceSearchView(
                    closeAction: { store.send(.pinEditSearchDismissed) },
                    resultSelectedAction: { store.send(.pinEditSearchResultSelected($0)) }
                )
            case .details:
                CourseRegistrationDetailsView(
                    state: store.state.details,
                    send: { store.send(.details($0)) }
                )
            }
        }
        .rodiSnackbar(message: store.state.errorMessage)
        .task(id: store.state.errorMessage) {
            guard store.state.errorMessage != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            store.send(.errorDismissed)
        }
        .overlay {
            if store.state.isRegistrationDiscardConfirmationPresented {
                ReviewDiscardConfirmationView(
                    send: { action in
                        switch action {
                        case .discard:
                            store.send(.registrationDiscardConfirmed)
                        case .keepWriting:
                            store.send(.registrationDiscardCancelled)
                        }
                    },
                    confirmAction: RegistrationDiscardAction.discard,
                    cancelAction: RegistrationDiscardAction.keepWriting
                )
            }
        }
        .overlay {
            if store.state.details.isSubmitting {
                CourseRegistrationSubmittingDialog()
            } else if store.state.details.isCompletionPresented {
                CourseRegistrationCompletionDialog(
                    confirmAction: { store.send(.details(.completionConfirmed)) }
                )
            }
        }
        .onChange(of: store.state.tutorialCompletionRevision) { revision in
            guard revision > handledCompletionRevision else { return }
            handledCompletionRevision = revision
            tutorialCompletedAction()
        }
        .onChange(of: store.state.courseRegistrationCompletionRevision) { revision in
            guard revision > handledCourseRegistrationCompletionRevision else { return }
            handledCourseRegistrationCompletionRevision = revision
            courseRegistrationCompletedAction()
        }
        .onChange(of: store.state.courseRegistrationExitRevision) { revision in
            guard revision > handledCourseRegistrationExitRevision else { return }
            handledCourseRegistrationExitRevision = revision
            closeAction()
        }
    }

}

private enum RegistrationDiscardAction {
    case discard
    case keepWriting
}

private struct CourseRegistrationEntryView: View {
    let waypoints: [CourseRegistrationWaypoint]
    let selectedPlaces: [CourseRegistrationInputTarget: CourseRegistrationSelectedPlace]
    let routePath: [RodiCoordinate]
    let isRouteLoading: Bool
    let map: CourseRegistrationMapState
    let closeAction: () -> Void
    let addWaypointAction: () -> Void
    let removeWaypointAction: (UUID) -> Void
    let inputTargetTappedAction: (CourseRegistrationInputTarget) -> Void
    let currentLocationAction: () -> Void
    let mapViewportChangedAction: (RodiCoordinate, Bool) -> Void
    let routePointTappedAction: (Int) -> Void
    let placeSelectionAction: () -> Void
    let selectionCompletionAction: () -> Void
    let registrationCompletionAction: () -> Void

    var body: some View {
        ZStack {
            mapView
                .ignoresSafeArea()

            // 위치를 임시 선택한 뒤에도 완료 전까지는 중앙 핀을 유지한다.
            // 그래야 선택한 좌표가 지도 중심의 핀 꼭지점과 일치하는지 즉시 확인할 수 있다.
            if let target = map.selectionTarget {
                Image(target.movingPinAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: CourseRegistrationMapPinLayout.size,
                        height: CourseRegistrationMapPinLayout.size
                    )
                    .offset(y: CourseRegistrationMapPinLayout.centerAlignmentOffsetY)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    CourseRegistrationHeader(title: "코스 등록", closeAction: closeAction)
                    CourseRegistrationLocationInputs(
                        waypoints: waypoints,
                        selectedPlaces: selectedPlaces,
                        isEditable: map.selectionTarget == nil,
                        addWaypointAction: addWaypointAction,
                        removeWaypointAction: removeWaypointAction,
                        inputTargetTappedAction: inputTargetTappedAction
                    )
                }
                .background(RodiColor.white)

                Spacer()

                HStack {
                    Spacer()
                    CurrentLocationButton(
                        isActive: map.isCurrentLocationActive,
                        action: currentLocationAction
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

                bottomBar
            }
            .zIndex(1)
        }
        .background(RodiColor.white.ignoresSafeArea())
    }

    private var mapView: some View {
        KakaoMapContainerView(
            cameraTarget: map.cameraTarget,
            cameraRequestID: map.cameraRequestID,
            animatedCameraRequestID: nil,
            cameraFocus: .normal,
            userLocation: nil,
            userHeadingDegrees: nil,
            routeOverlay: routeOverlay,
            mapMarkers: [],
            logoBottomInset: 0,
            cameraBottomInset: 0,
            isInteractionEnabled: true,
            visibilityState: .interactive,
            onEvent: { event in
                switch event {
                case let .viewportChanged(center, _, _, isUserInitiated):
                    mapViewportChangedAction(center, isUserInitiated)
                case let .routePointTap(pointID):
                    routePointTappedAction(pointID)
                default:
                    break
                }
            }
        )
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let target = map.selectionTarget {
            CourseRegistrationSelectionBar(
                targetTitle: target.selectionTitle,
                isSelecting: map.isAddressResolving,
                isSelectionEnabled: map.candidateCoordinate != nil && !map.isAddressResolving,
                isCompletionEnabled: map.hasSelectedCurrentTarget && !map.isAddressResolving,
                placeSelectionAction: placeSelectionAction,
                completionAction: selectionCompletionAction
            )
        } else {
            CourseRegistrationReadyBar(
                isCompletionEnabled: selectedPlaces[.start] != nil && selectedPlaces[.destination] != nil,
                isRouteLoading: isRouteLoading,
                addWaypointAction: addWaypointAction,
                completionAction: registrationCompletionAction
            )
        }
    }

    private var routeOverlay: RodiRouteOverlay? {
        let points = confirmedPoints
        guard !points.isEmpty else { return nil }
        return RodiRouteOverlay(
            courseID: 0,
            points: points,
            path: routePath,
            isRoadRoute: routePath.count >= 2
        )
    }

    private var confirmedPoints: [RodiRouteOverlayPoint] {
        var points: [RodiRouteOverlayPoint] = []
        if let start = selectedPlaces[.start] {
            points.append(.init(
                id: points.count,
                sequence: points.count,
                role: .start,
                name: start.name,
                coordinate: start.coordinate
            ))
        }
        for waypoint in waypoints {
            guard let place = selectedPlaces[.waypoint(waypoint.id)] else { continue }
            points.append(.init(
                id: points.count,
                sequence: points.count,
                role: .waypoint,
                name: place.name,
                coordinate: place.coordinate
            ))
        }
        if let destination = selectedPlaces[.destination] {
            points.append(.init(
                id: points.count,
                sequence: points.count,
                role: .end,
                name: destination.name,
                coordinate: destination.coordinate
            ))
        }
        return points
    }
}

private struct CourseRegistrationPinEditView: View {
    let pinEdit: CourseRegistrationPinEditingReducer.State
    let waypoints: [CourseRegistrationWaypoint]
    let selectedPlaces: [CourseRegistrationInputTarget: CourseRegistrationSelectedPlace]
    let mapViewportChangedAction: (RodiCoordinate, Bool) -> Void
    let currentLocationAction: () -> Void
    let addressTappedAction: () -> Void
    let selectionAction: () -> Void
    let retryAction: () -> Void
    let completionAction: ([RodiRouteOverlayPoint]) -> Void
    let backAction: () -> Void

    var body: some View {
        ZStack {
            mapView
                .ignoresSafeArea()

            if pinEdit.temporaryPlace == nil {
                Image(pinEdit.target.movingPinAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: CourseRegistrationMapPinLayout.size,
                        height: CourseRegistrationMapPinLayout.size
                    )
                    .offset(y: CourseRegistrationMapPinLayout.centerAlignmentOffsetY)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    CourseRegistrationHeader(title: "핀 수정하기", closeAction: backAction)
                    addressRow
                }
                .background(RodiColor.white)

                Spacer()

                HStack {
                    Spacer()
                    CurrentLocationButton(
                        isActive: pinEdit.isCurrentLocationActive,
                        action: currentLocationAction
                    )
                    .disabled(pinEdit.temporaryPlace != nil)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

                CourseRegistrationDualButtonBar(
                    leadingTitle: pinEdit.temporaryPlace == nil
                        ? (pinEdit.isAddressResolving ? "주소 확인 중..." : pinEdit.target.selectionTitle)
                        : "다시하기",
                    isLeadingEnabled: pinEdit.temporaryPlace != nil || canSelectCandidate,
                    leadingAction: pinEdit.temporaryPlace == nil ? selectionAction : retryAction,
                    trailingTitle: pinEdit.isSaving ? "저장 중..." : "완료",
                    isTrailingEnabled: !pinEdit.isSaving,
                    trailingAction: { completionAction(overlayPoints) }
                )
            }
            .zIndex(1)
        }
        .background(RodiColor.white.ignoresSafeArea())
    }

    private var mapView: some View {
        KakaoMapContainerView(
            cameraTarget: pinEdit.cameraTarget,
            cameraRequestID: pinEdit.cameraRequestID,
            animatedCameraRequestID: nil,
            cameraFocus: .normal,
            userLocation: nil,
            userHeadingDegrees: nil,
            routeOverlay: routeOverlay,
            mapMarkers: [],
            logoBottomInset: 0,
            cameraBottomInset: 0,
            isInteractionEnabled: pinEdit.temporaryPlace == nil,
            visibilityState: .interactive,
            onEvent: { event in
                guard case let .viewportChanged(center, _, _, isUserInitiated) = event else {
                    return
                }
                mapViewportChangedAction(center, isUserInitiated)
            }
        )
    }

    private var addressRow: some View {
        Button(action: addressTappedAction) {
            HStack(spacing: 8) {
                Image(pinEdit.target.inputIconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                Text(pinEdit.temporaryPlace?.name ?? pinEdit.candidateAddress ?? pinEdit.originalPlace.name)
                    .font(.pretendard(size: 15, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(RodiColor.gray800)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(RodiColor.white)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(RodiColor.gray300, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityLabel("\(pinEdit.target.selectionTitle) 주소 검색")
    }

    private var canSelectCandidate: Bool {
        pinEdit.candidateCoordinate != nil
            && !pinEdit.isAddressResolving
    }

    private var routeOverlay: RodiRouteOverlay? {
        let points = overlayPoints
        guard !points.isEmpty else { return nil }
        return RodiRouteOverlay(courseID: 0, points: points, path: [], isRoadRoute: false)
    }

    private var overlayPoints: [RodiRouteOverlayPoint] {
        var points: [RodiRouteOverlayPoint] = []
        let targets = orderedTargets

        for (index, target) in targets.enumerated() {
            guard target != pinEdit.target || pinEdit.temporaryPlace != nil else { continue }
            let place = target == pinEdit.target
                ? pinEdit.temporaryPlace
                : selectedPlaces[target]
            guard let place else { continue }
            points.append(.init(
                id: index,
                sequence: index,
                role: target.routePointRole,
                name: place.name,
                coordinate: place.coordinate
            ))
        }
        return points
    }

    private var orderedTargets: [CourseRegistrationInputTarget] {
        var targets: [CourseRegistrationInputTarget] = []
        if selectedPlaces[.start] != nil { targets.append(.start) }
        targets += waypoints.compactMap { waypoint in
            selectedPlaces[.waypoint(waypoint.id)] == nil ? nil : .waypoint(waypoint.id)
        }
        if selectedPlaces[.destination] != nil { targets.append(.destination) }
        return targets
    }
}

private struct CourseRegistrationSelectionBar: View {
    let targetTitle: String
    let isSelecting: Bool
    let isSelectionEnabled: Bool
    let isCompletionEnabled: Bool
    let placeSelectionAction: () -> Void
    let completionAction: () -> Void

    var body: some View {
        CourseRegistrationDualButtonBar(
            leadingTitle: isSelecting ? "주소 확인 중..." : targetTitle,
            isLeadingEnabled: isSelectionEnabled,
            leadingAction: placeSelectionAction,
            trailingTitle: "완료",
            isTrailingEnabled: isCompletionEnabled,
            trailingAction: completionAction
        )
    }
}

private struct CourseRegistrationReadyBar: View {
    let isCompletionEnabled: Bool
    let isRouteLoading: Bool
    let addWaypointAction: () -> Void
    let completionAction: () -> Void

    var body: some View {
        CourseRegistrationDualButtonBar(
            leadingTitle: "경유지 추가",
            isLeadingEnabled: !isRouteLoading,
            leadingAction: addWaypointAction,
            trailingTitle: isRouteLoading ? "경로 불러오는 중..." : "완료",
            isTrailingEnabled: isCompletionEnabled && !isRouteLoading,
            trailingAction: completionAction
        )
    }
}

private struct CourseRegistrationDualButtonBar: View {
    let leadingTitle: String
    let isLeadingEnabled: Bool
    let leadingAction: () -> Void
    let trailingTitle: String
    let isTrailingEnabled: Bool
    let trailingAction: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Button(action: leadingAction) {
                Text(leadingTitle)
                    .rodiTypography(.buttonMedium)
                    .foregroundStyle(isLeadingEnabled ? RodiColor.gray800 : RodiColor.gray500)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(RodiColor.gray300, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!isLeadingEnabled)

            Button(action: trailingAction) {
                Text(trailingTitle)
                    .rodiTypography(.buttonMedium)
                    .foregroundStyle(isTrailingEnabled ? RodiColor.white : RodiColor.gray500)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(isTrailingEnabled ? RodiColor.primary : RodiColor.gray300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!isTrailingEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(RodiColor.gray200)
                .frame(height: 1)
        }
        .background(RodiColor.white)
    }
}

private struct CourseRegistrationLocationInputs: View {
    let waypoints: [CourseRegistrationWaypoint]
    let selectedPlaces: [CourseRegistrationInputTarget: CourseRegistrationSelectedPlace]
    let isEditable: Bool
    let addWaypointAction: () -> Void
    let removeWaypointAction: (UUID) -> Void
    let inputTargetTappedAction: (CourseRegistrationInputTarget) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if waypoints.isEmpty {
                ZStack(alignment: .trailing) {
                    VStack(spacing: 10) {
                        CourseRegistrationLocationRow(
                            iconName: "ic_course_start",
                            text: selectedPlaces[.start]?.name ?? "출발지 입력",
                            isPlaceholder: selectedPlaces[.start] == nil,
                            tapAction: { inputTargetTappedAction(.start) }
                        )
                        CourseRegistrationLocationRow(
                            iconName: "ic_course_destination",
                            text: selectedPlaces[.destination]?.name ?? "도착지 입력",
                            isPlaceholder: selectedPlaces[.destination] == nil,
                            tapAction: { inputTargetTappedAction(.destination) }
                        )
                    }

                    Button(action: addWaypointAction) {
                        CourseRegistrationCircleIcon(kind: .plus)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    // 44pt hit area 안에서 24pt 아이콘의 trailing을 행 기준 20pt로 둔다.
                    .padding(.trailing, 10)
                    .disabled(!isEditable)
                    .accessibilityLabel("경유지 추가")
                }
            } else {
                VStack(spacing: 10) {
                    CourseRegistrationLocationRow(
                        iconName: "ic_course_start",
                        text: selectedPlaces[.start]?.name ?? "출발지 입력",
                        isPlaceholder: selectedPlaces[.start] == nil,
                        tapAction: { inputTargetTappedAction(.start) }
                    )
                    ForEach(waypoints) { waypoint in
                        CourseRegistrationLocationRow(
                            iconName: "ic_course_waypoint",
                            text: selectedPlaces[.waypoint(waypoint.id)]?.name ?? "경유지 입력",
                            isPlaceholder: selectedPlaces[.waypoint(waypoint.id)] == nil,
                            trailingControl: .minus { removeWaypointAction(waypoint.id) },
                            isInteractive: true,
                            tapAction: { inputTargetTappedAction(.waypoint(waypoint.id)) }
                        )
                    }
                    CourseRegistrationLocationRow(
                        iconName: "ic_course_destination",
                        text: selectedPlaces[.destination]?.name ?? "도착지 입력",
                        isPlaceholder: selectedPlaces[.destination] == nil,
                        trailingControl: waypoints.count < 3 ? .plus(addWaypointAction) : nil,
                        isInteractive: isEditable,
                        tapAction: { inputTargetTappedAction(.destination) }
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 5)
    }
}

private struct CourseRegistrationLocationRow: View {
    enum TrailingControl {
        case plus(() -> Void)
        case minus(() -> Void)
    }

    let iconName: String
    let text: String
    let isPlaceholder: Bool
    var trailingControl: TrailingControl? = nil
    var isInteractive = true
    var tapAction: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: { tapAction?() }) {
                Rectangle()
                    .fill(RodiColor.white.opacity(0.001))
            }
            .buttonStyle(.plain)
            .disabled(tapAction == nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())

            HStack(spacing: 8) {
                Image(iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                Text(text)
                    .font(.pretendard(size: 15, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(isPlaceholder ? RodiColor.gray500 : RodiColor.gray800)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 12)
            .padding(.trailing, trailingControl == nil ? 12 : 52)
            .allowsHitTesting(false)

            if let trailingControl {
                trailingButton(for: trailingControl)
                    .padding(.trailing, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(RodiColor.white)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(RodiColor.gray300, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func trailingButton(for control: TrailingControl) -> some View {
        switch control {
        case .plus(let action):
            Button(action: action) {
                CourseRegistrationCircleIcon(kind: .plus)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .disabled(!isInteractive)
            .accessibilityLabel("경유지 추가")
        case .minus(let action):
            Button(action: action) {
                CourseRegistrationCircleIcon(kind: .minus)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .disabled(!isInteractive)
            .accessibilityLabel("경유지 삭제")
        }
    }
}

private struct CourseRegistrationCircleIcon: View {
    enum Kind { case plus, minus }

    let kind: Kind

    var body: some View {
        ZStack {
            switch kind {
            case .plus:
                Image("ic_plus_circle")
                Image("ic_plus_circle_vertical")
                Image("ic_plus_circle_horizontal")
            case .minus:
                Image("ic_minus_circle")
                Image("ic_minus_circle_horizontal")
            }
        }
        .frame(width: 24, height: 24)
    }
}

struct CourseRegistrationHeader: View {
    let title: String
    let closeAction: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .rodiTypography(.headline1)
                .foregroundStyle(RodiColor.black)
            HStack {
                Button(action: closeAction) {
                    Image("ic_chevron_left_24")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("뒤로 가기")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }
}
