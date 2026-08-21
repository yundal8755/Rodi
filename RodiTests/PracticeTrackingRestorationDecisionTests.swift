import XCTest
@testable import Rodi

final class PracticeTrackingRestorationDecisionTests: XCTestCase {

    func testHeadingSessionWithinGracePeriodCanContinue() {
        let session = makeSession(phase: .headingToCourse)
        let measurement = makeMeasurement(id: session.id, handoffAt: .now.addingTimeInterval(-14 * 60))

        XCTAssertEqual(
            PracticeTrackingRestorationDecision.make(
                session: session,
                measurement: measurement,
                now: .now,
                approachGracePeriod: 15 * 60
            ),
            .continueApproach
        )
    }

    func testExpiredHeadingSessionIsDiscarded() {
        let session = makeSession(phase: .headingToCourse)
        let measurement = makeMeasurement(id: session.id, handoffAt: .now.addingTimeInterval(-16 * 60))

        XCTAssertEqual(
            PracticeTrackingRestorationDecision.make(
                session: session,
                measurement: measurement,
                now: .now,
                approachGracePeriod: 15 * 60
            ),
            .discardApproach
        )
    }

    func testDrivingSessionIsInterruptedAfterProcessRestart() {
        let session = makeSession(phase: .drivingCourse)

        XCTAssertEqual(
            PracticeTrackingRestorationDecision.make(
                session: session,
                measurement: makeMeasurement(id: session.id, handoffAt: .now),
                now: .now,
                approachGracePeriod: 15 * 60
            ),
            .interruptDriving
        )
    }

    func testMismatchedMeasurementDoesNotResumeApproach() {
        let session = makeSession(phase: .headingToCourse)

        XCTAssertEqual(
            PracticeTrackingRestorationDecision.make(
                session: session,
                measurement: makeMeasurement(id: UUID(), handoffAt: .now),
                now: .now,
                approachGracePeriod: 15 * 60
            ),
            .discardApproach
        )
    }

    func testRouteOnlyMeasurementIsNotReviewEligibleBeforeCertification() {
        var measurement = makeMeasurement(id: UUID(), handoffAt: .now)
        measurement.status = .awaitingReturn

        XCTAssertFalse(measurement.isReviewEligible)
    }

    func testCourseContainingParkingPracticeTypeIsReviewWritable() {
        XCTAssertFalse(
            makePracticeItem(types: [PlacePracticeType.parking.rawValue, PlacePracticeType.straight.rawValue])
                .isParkingPractice
        )
    }

    func testParkingPracticeIsNotReviewWritable() {
        XCTAssertTrue(makePracticeItem(types: [PlacePracticeType.parking.rawValue]).isParkingPractice)
    }

    #if DEBUG
    func testDebugCourseVisitIsEligibleAfterFiveSecondExternalHandoff() {
        let measurement = makeMeasurement(
            id: UUID(),
            handoffAt: .now.addingTimeInterval(-5)
        )

        XCTAssertTrue(
            PracticeReturnReducer.shouldRecordDebugCourseVisit(
                measurement: measurement,
                now: .now
            )
        )
    }

    func testDebugCourseVisitDoesNotApplyToParking() {
        var measurement = makeMeasurement(
            id: UUID(),
            handoffAt: .now.addingTimeInterval(-5)
        )
        measurement = .init(
            id: measurement.id,
            placeID: measurement.placeID,
            placeName: measurement.placeName,
            placeType: .parking,
            mode: measurement.mode,
            externalHandoffAt: measurement.externalHandoffAt,
            status: measurement.status
        )

        XCTAssertFalse(
            PracticeReturnReducer.shouldRecordDebugCourseVisit(
                measurement: measurement,
                now: .now
            )
        )
    }
    #endif

    private func makeSession(phase: PracticeTrackingPhase) -> PracticeTrackingSession {
        .init(
            id: UUID(),
            courseID: 1,
            courseName: "연습 코스",
            placeType: .course,
            rabbitAssetName: nil,
            routePath: [
                .init(latitude: 37.5, longitude: 127.0),
                .init(latitude: 37.51, longitude: 127.01)
            ],
            cumulativeRouteDistanceMeters: [0, 100],
            startedAt: .now,
            phase: phase,
            drivingStartedAt: nil,
            lastAcceptedLocationAt: nil,
            courseProgress: 0,
            activeDrivingSeconds: 0,
            matchedSampleCount: 0,
            initialDistanceToCourseStartMeters: nil,
            distanceToCourseStartMeters: nil,
            lastMatchedLocationAt: nil,
            initialMatchedRouteDistanceMeters: nil,
            furthestMatchedRouteDistanceMeters: nil,
            drivenRouteDistanceMeters: nil,
            completedAt: nil
        )
    }

    private func makeMeasurement(id: UUID, handoffAt: Date) -> PracticeMeasurement {
        .init(
            id: id,
            placeID: 1,
            placeName: "연습 코스",
            mode: .gpsTracking,
            externalHandoffAt: handoffAt,
            status: .tracking
        )
    }

    private func makePracticeItem(types: [String]) -> MyPracticeItem {
        .init(
            id: 1,
            placeID: 1,
            placeName: "연습 장소",
            practiceTypes: types,
            status: .visited,
            visitCount: 1,
            lastActivityAt: .now,
            hasReview: false,
            isDeleted: false
        )
    }
}
