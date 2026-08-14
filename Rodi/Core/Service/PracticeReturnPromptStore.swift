//
//  PracticeReturnPromptStore.swift
//  Rodi
//

import Foundation

struct PracticeReturnPrompt: Codable, Equatable {
    let id: UUID
    let placeID: Int
    let placeName: String

    init(placeID: Int, placeName: String) {
        id = UUID()
        self.placeID = placeID
        self.placeName = placeName
    }
}

protocol PracticeReturnPromptStoring {
    func load() -> PracticeReturnPrompt?
    func save(_ prompt: PracticeReturnPrompt)
    func remove(_ prompt: PracticeReturnPrompt)
}

struct PracticeReturnPromptStore: PracticeReturnPromptStoring {
    private enum Key {
        static let prompt = "rodi.practice-return-prompt"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> PracticeReturnPrompt? {
        guard let data = userDefaults.data(forKey: Key.prompt) else { return nil }
        return try? JSONDecoder().decode(PracticeReturnPrompt.self, from: data)
    }

    func save(_ prompt: PracticeReturnPrompt) {
        guard let data = try? JSONEncoder().encode(prompt) else { return }
        userDefaults.set(data, forKey: Key.prompt)
    }

    func remove(_ prompt: PracticeReturnPrompt) {
        guard load()?.id == prompt.id else { return }
        userDefaults.removeObject(forKey: Key.prompt)
    }
}
