//
//  MyFeatureDependencies.swift
//  Rodi
//

import Foundation

/// My feature가 실제로 사용하는 의존성만 묶는다.
/// App 조립 객체를 View 계층 전체로 전달하지 않기 위한 feature 경계다.
struct MyFeatureDependencies {
    let authRepository: AuthRepository
    let memberRepository: MemberRepository
    let placeRepository: PlaceRepository
    let practiceRepository: PracticeRepository
    let reviewRepository: ReviewRepository
    let courseRepository: CourseRepository
    let recentLoginProviderStore: RecentLoginProviderStore
    let levelUpPresentationStore: LevelUpPresentationStoring

    init(appDependencies: AppDependencies) {
        authRepository = appDependencies.authRepository
        memberRepository = appDependencies.memberRepository
        placeRepository = appDependencies.placeRepository
        practiceRepository = appDependencies.practiceRepository
        reviewRepository = appDependencies.reviewRepository
        courseRepository = appDependencies.courseRepository
        recentLoginProviderStore = appDependencies.recentLoginProviderStore
        levelUpPresentationStore = appDependencies.levelUpPresentationStore
    }
}
