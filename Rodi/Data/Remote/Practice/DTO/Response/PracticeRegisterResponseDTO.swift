import Foundation

struct PracticeRegisterResponseDTO: Decodable {
    let practiceID: Int

    private enum CodingKeys: String, CodingKey {
        case practiceID = "practiceId"
    }
}
