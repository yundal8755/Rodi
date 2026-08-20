//
//  PracticeLiveActivityAttributes.swift
//  RodiPracticeLiveActivity
//

import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct PracticeLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let phaseRawValue: String
        let approachProgress: Double
        let progress: Double
        let distanceToCourseStartMeters: Int?
        /// 코스 방문 기록 저장 상태입니다. 이전 Activity와 주차장은 nil을 유지합니다.
        let completionRecordStateRawValue: String?

        init(
            phaseRawValue: String,
            approachProgress: Double,
            progress: Double,
            distanceToCourseStartMeters: Int?,
            completionRecordStateRawValue: String? = nil
        ) {
            self.phaseRawValue = phaseRawValue
            self.approachProgress = approachProgress
            self.progress = progress
            self.distanceToCourseStartMeters = distanceToCourseStartMeters
            self.completionRecordStateRawValue = completionRecordStateRawValue
        }
    }

    let sessionID: UUID
    let courseID: Int
    let courseName: String
    let placeTypeRawValue: String
    let rabbitAssetName: String
}
