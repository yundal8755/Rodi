//
//  PracticeTrackingView.swift
//  Rodi
//

import SwiftUI

/// 연습 추적 Feature의 lifecycle adapter와 연속 측정 dialog를 조립한다.
struct PracticeTrackingView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var service: PracticeTrackingService
    
    let state: PracticeTrackingReducer.State
    let canPresentReviewPrompt: Bool
    let send: (PracticeTrackingReducer.Action) -> Void
    
    var body: some View {
        ZStack {
            if let measurement = state.practiceReturn.activeMeasurementContinuation {
                PracticeTrackingContinuationDialog(
                    courseName: measurement.placeName,
                    continueAction: { send(.activeMeasurementContinued) },
                    endAction: { send(.activeMeasurementEnded) }
                )
            }
            
        }
        .onReceive(service.$certificationRevision) { _ in
            guard scenePhase == .active else { return }
            send(.certificationRevisionChanged(canPresentPrompt: canPresentReviewPrompt))
        }

    }
}
