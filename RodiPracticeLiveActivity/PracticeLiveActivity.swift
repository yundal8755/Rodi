//
//  PracticeLiveActivity.swift
//  RodiPracticeLiveActivity
//

import ActivityKit
import SwiftUI
import WidgetKit

private enum PracticeActivityPalette {
    static let primary = Color(red: 0.337, green: 0.251, blue: 1)
    static let primary400 = Color(red: 0.439, green: 0.384, blue: 1)
    static let primary100 = Color(red: 0.859, green: 0.851, blue: 1)
    static let gray100 = Color(red: 0.961, green: 0.961, blue: 0.961)
    static let text = Color(red: 0.133, green: 0.133, blue: 0.133)
    static let secondaryText = Color(red: 0.384, green: 0.384, blue: 0.384)
    static let gray600 = Color(red: 0.463, green: 0.463, blue: 0.463)
}

@main
struct RodiPracticeLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            RodiPracticeLiveActivity()
        }
    }
}

@available(iOS 16.1, *)
struct RodiPracticeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PracticeLiveActivityAttributes.self) { context in
            PracticeActivityView(context: context)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(PracticeActivityPalette.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(
                        PracticeActivityView.phaseTitle(for: context.state),
                        systemImage: PracticeActivityView.phaseIcon(for: context.state)
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PracticeActivityView.phaseColor(for: context.state))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(compactValue(for: context.state))
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PracticeActivityView(context: context)
                }
            } compactLeading: {
                Image(systemName: context.state.phaseRawValue == "completed" ? "checkmark.circle.fill" : "car.fill")
                    .foregroundStyle(PracticeActivityPalette.primary400)
            } compactTrailing: {
                Text(compactValue(for: context.state))
                    .font(.caption2.monospacedDigit().weight(.semibold))
            } minimal: {
                Image(systemName: context.state.phaseRawValue == "completed" ? "checkmark" : "car.fill")
            }
            .keylineTint(PracticeActivityPalette.primary400)
        }
    }

    private func compactValue(for state: PracticeLiveActivityAttributes.ContentState) -> String {
        if state.phaseRawValue == "completed" {
            return "완료"
        }
        if state.phaseRawValue == "headingToCourse", let distance = state.distanceToCourseStartMeters {
            return PracticeActivityView.formattedDistance(distance)
        }
        return "\(Int((state.progress * 100).rounded()))%"
    }
}

@available(iOS 16.1, *)
private struct PracticeActivityView: View {
    let context: ActivityViewContext<PracticeLiveActivityAttributes>

    var body: some View {
        Group {
            switch context.state.phaseRawValue {
            case "headingToCourse":
                headingToCourseContent
            case "drivingCourse":
                drivingCourseContent
            case "completed":
                completionContent
            default:
                completionContent
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PracticeActivityPalette.gray100)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    static func formattedDistance(_ meters: Int) -> String {
        if meters >= 1_000 {
            return String(format: "%.1fkm", Double(meters) / 1_000)
        }
        return "\(meters)m"
    }

    private var headingToCourseContent: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                RodiLogoView()

                VStack(alignment: .leading, spacing: 4) {
                    Text("연습 코스로 이동하고 있어요")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PracticeActivityPalette.primary)
                    Text("코스에 도착하면 Rodi가 주행을 기록해 드릴게요.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PracticeActivityPalette.secondaryText)
                        .lineLimit(1)
                }
                .padding(.trailing, 60)
            }

            Image("img_live_activity_heading")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)
                .padding(.top, 11)
        }
    }

    private var drivingCourseContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                RodiLogoView()
                VStack(alignment: .leading, spacing: 4) {
                    (Text(context.attributes.courseName).foregroundColor(PracticeActivityPalette.primary)
                    + Text(" 코스 주행 중").foregroundColor(PracticeActivityPalette.text))
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text("Rodi가 코스 주행을 확인하고 있어요.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PracticeActivityPalette.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                PracticeProgressBar(progress: context.state.progress)
                HStack {
                    Text("출발").foregroundStyle(PracticeActivityPalette.primary)
                    Spacer(minLength: 0)
                    Text("도착").foregroundStyle(PracticeActivityPalette.gray600)
                }
                .font(.system(size: 13, weight: .medium))
            }
        }
    }

    private var completionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            RodiLogoView()
            VStack(alignment: .leading, spacing: 4) {
                Text("오늘의 운전연습을 완료했어요!")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PracticeActivityPalette.primary)
                VStack(alignment: .leading, spacing: 0) {
                    Text("오늘도 한 걸음 성장했어요.")
                    Text("Rodi로 돌아가 기록을 남겨주세요.")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PracticeActivityPalette.secondaryText)
            }
            Text("기록하러 가기")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(PracticeActivityPalette.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    static func phaseTitle(for state: PracticeLiveActivityAttributes.ContentState) -> String {
        switch state.phaseRawValue {
        case "headingToCourse": "연습코스로 이동 중"
        case "drivingCourse": "코스 주행 중"
        case "completed": "코스 주행 완료"
        default: "연습 기록 종료"
        }
    }

    static func phaseIcon(for state: PracticeLiveActivityAttributes.ContentState) -> String {
        switch state.phaseRawValue {
        case "headingToCourse": "location.fill"
        case "drivingCourse": "car.fill"
        case "completed": "checkmark.circle.fill"
        default: "stop.circle.fill"
        }
    }

    static func phaseColor(for state: PracticeLiveActivityAttributes.ContentState) -> Color {
        PracticeActivityPalette.primary
    }
}

@available(iOS 16.1, *)
private struct RodiLogoView: View {
    var body: some View {
        Image("ic_live_activity_rodi_logo")
            .resizable()
            .scaledToFit()
            .frame(width: 48, height: 15)
            .accessibilityLabel("로디")
    }
}

@available(iOS 16.1, *)
private struct PracticeProgressBar: View {
    let progress: Double

    var body: some View {
        ProgressView(value: min(max(progress, 0), 1), total: 1)
            .tint(PracticeActivityPalette.primary)
            .progressViewStyle(.linear)
            .frame(height: 6)
            .background(PracticeActivityPalette.primary100, in: Capsule())
            .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("연습 진행 상태 \(Int((progress * 100).rounded()))퍼센트")
    }
}
