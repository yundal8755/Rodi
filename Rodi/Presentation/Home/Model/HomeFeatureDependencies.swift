//
//  HomeFeatureDependencies.swift
//  Rodi
//

struct HomeFeatureDependencies {
    let tokenStore: TokenStoring
    let placeRepository: PlaceRepository
    let practiceRepository: PracticeRepository
    let recentSearchRepository: RecentSearchRepository
    let reviewRepository: ReviewRepository
    let memberRepository: MemberRepository
    let practiceMeasurementStore: PracticeMeasurementStoring
    let drivePracticeService: DrivePracticeService
    let snackbarService: SnackbarService

    init(appDependencies: AppDependencies) {
        tokenStore = appDependencies.tokenStore
        placeRepository = appDependencies.placeRepository
        practiceRepository = appDependencies.practiceRepository
        recentSearchRepository = appDependencies.recentSearchRepository
        reviewRepository = appDependencies.reviewRepository
        memberRepository = appDependencies.memberRepository
        practiceMeasurementStore = appDependencies.practiceMeasurementStore
        drivePracticeService = appDependencies.drivePracticeService
        snackbarService = appDependencies.snackbarService
    }
}
