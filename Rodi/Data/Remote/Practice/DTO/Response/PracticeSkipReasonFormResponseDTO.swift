import Foundation

struct PracticeSkipReasonFormResponseDTO: Decodable {
    let options: [PracticeSkipReasonOptionDTO]
}

struct PracticeSkipReasonOptionDTO: Decodable {
    let code: String
    let label: String
    let order: Int
    let requiresTextInput: Bool
    let textInputPlaceholder: String?
    let textInputMaxLength: Int?
}
