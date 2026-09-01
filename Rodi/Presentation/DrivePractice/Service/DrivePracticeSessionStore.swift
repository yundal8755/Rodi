//
//  DrivePracticeSessionStore.swift
//  Rodi
//

import Foundation

struct DrivePracticeSessionStore {
    private enum Key {
        static let activeSession = "rodi.practiceTracking.activeSession"
    }

    private let persistence = UserDefaultsCodableStore<DrivePracticeSession>(key: Key.activeSession)

    func load() -> DrivePracticeSession? {
        do {
            return try persistence.decode()
        } catch {
            RodiLogger.warning("Practice tracking session restore failed")
            clear()
            return nil
        }
    }

    func save(_ session: DrivePracticeSession) {
        persistence.save(session)
    }

    func clear() {
        persistence.remove()
    }
}
