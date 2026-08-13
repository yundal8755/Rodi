//
//  KakaoLocalSearchModel.swift
//  Rodi
//

import Foundation

struct KakaoLocalRegionSuggestion: Equatable, Identifiable {
    let id: String
    let displayName: String
    let searchQuery: String
}

struct KakaoLocalSearchItem: Equatable, Identifiable {
    let id: String
    let title: String
    let address: String
    let category: String?
    let phone: String?
}

struct KakaoLocalSearchPage: Equatable {
    let items: [KakaoLocalSearchItem]
}
