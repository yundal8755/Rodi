import SwiftUI

struct CourseRegistrationLocationInputs: View {
    let waypoints: [CourseRegistrationWaypoint]
    let selectedPlaces: [CourseRegistrationInputTarget: CourseRegistrationSelectedPlace]
    let isEditable: Bool
    let send: (CourseRegistrationMapSelectionReducer.Action) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if waypoints.isEmpty {
                ZStack(alignment: .trailing) {
                    VStack(spacing: 10) {
                        row(for: .start, title: "출발지 입력")
                        row(for: .destination, title: "도착지 입력")
                    }

                    Button(action: { send(.waypointAddTapped) }) {
                        CourseRegistrationCircleIcon(kind: .plus)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .padding(.trailing, 10)
                    .disabled(!isEditable)
                    .accessibilityLabel("경유지 추가")
                }
            } else {
                VStack(spacing: 10) {
                    row(for: .start, title: "출발지 입력")

                    ForEach(waypoints) { waypoint in
                        CourseRegistrationLocationRow(
                            iconName: "ic_course_waypoint",
                            text: selectedPlaces[.waypoint(waypoint.id)]?.name ?? "경유지 입력",
                            isPlaceholder: selectedPlaces[.waypoint(waypoint.id)] == nil,
                            trailingControl: .minus { send(.waypointRemoveTapped(waypoint.id)) },
                            isInteractive: isEditable,
                            tapAction: { send(.inputTargetTapped(.waypoint(waypoint.id))) }
                        )
                    }

                    CourseRegistrationLocationRow(
                        iconName: "ic_course_destination",
                        text: selectedPlaces[.destination]?.name ?? "도착지 입력",
                        isPlaceholder: selectedPlaces[.destination] == nil,
                        trailingControl: waypoints.count < 3
                            ? .plus { send(.waypointAddTapped) }
                            : nil,
                        isInteractive: isEditable,
                        tapAction: { send(.inputTargetTapped(.destination)) }
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 5)
    }

    private func row(for target: CourseRegistrationInputTarget, title: String) -> some View {
        CourseRegistrationLocationRow(
            iconName: target.inputIconName,
            text: selectedPlaces[target]?.name ?? title,
            isPlaceholder: selectedPlaces[target] == nil,
            isInteractive: isEditable,
            tapAction: { send(.inputTargetTapped(target)) }
        )
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
                    .padding(.trailing, 10)
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
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!isInteractive)
            .accessibilityLabel("경유지 추가")
        case .minus(let action):
            Button(action: action) {
                CourseRegistrationCircleIcon(kind: .minus)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
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
