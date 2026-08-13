//
//  KakaoLocalSearchService.swift
//  Rodi
//

import Foundation

enum KakaoLocalSearchError: Error {
    case missingAPIKey
    case invalidRequest
    case httpStatus(Int)
    case decodingFailed
    case networkFailed

    var userMessage: String {
        switch self {
        case .missingAPIKey:
            "KAKAO_REST_API_KEY가 설정되지 않았어요."
        case .invalidRequest:
            "검색 요청을 만들지 못했어요."
        case .httpStatus(let statusCode):
            switch statusCode {
            case 401:
                "REST API 키 인증에 실패했어요."
            case 403:
                "카카오맵 API 사용 설정을 확인해 주세요."
            case 429:
                "카카오맵 API 호출 한도를 초과했어요."
            default:
                "카카오 검색 요청에 실패했어요. (HTTP \(statusCode))"
            }
        case .decodingFailed:
            "카카오 검색 응답을 해석하지 못했어요."
        case .networkFailed:
            "네트워크 연결을 확인해 주세요."
        }
    }
}

struct KakaoLocalSearchService {
    func searchPlaces(
        query: String,
        size: Int = 15
    ) async throws -> KakaoLocalSearchPage {
        guard !KakaoConfiguration.restAPIKey.isEmpty else {
            throw KakaoLocalSearchError.missingAPIKey
        }

        var components = URLComponents(
            string: "https://dapi.kakao.com/v2/local/search/keyword.json"
        )
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "size", value: String(size))
        ]

        guard let url = components?.url else {
            throw KakaoLocalSearchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "KakaoAK \(KakaoConfiguration.restAPIKey)",
            forHTTPHeaderField: "Authorization"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if error is CancellationError {
                throw error
            }
            throw KakaoLocalSearchError.networkFailed
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KakaoLocalSearchError.networkFailed
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw KakaoLocalSearchError.httpStatus(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder()
                .decode(KakaoKeywordSearchResponseDTO.self, from: data)
                .toModel()
        } catch {
            throw KakaoLocalSearchError.decodingFailed
        }
    }
}

private struct KakaoKeywordSearchResponseDTO: Decodable {
    let documents: [Document]

    struct Document: Decodable {
        let id: String
        let placeName: String
        let categoryName: String
        let categoryGroupName: String
        let phone: String
        let addressName: String
        let roadAddressName: String

        enum CodingKeys: String, CodingKey {
            case id
            case placeName = "place_name"
            case categoryName = "category_name"
            case categoryGroupName = "category_group_name"
            case phone
            case addressName = "address_name"
            case roadAddressName = "road_address_name"
        }
    }

    func toModel() -> KakaoLocalSearchPage {
        KakaoLocalSearchPage(
            items: documents.map { document in
                KakaoLocalSearchItem(
                    id: "place-\(document.id)",
                    title: document.placeName,
                    address: document.roadAddressName.nonEmpty ?? document.addressName,
                    category: document.categoryGroupName.nonEmpty ?? document.categoryName.nonEmpty,
                    phone: document.phone.nonEmpty
                )
            }
        )
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
