import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// Apple Intelligence (Foundation Models, iOS 26+): natural-language smart
// playlists. Fully on-device, library metadata never leaves the iPhone.
// Everything is gated behind availability - devices without Apple
// Intelligence simply never see the feature.
enum IntelligenceService {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    struct SongDescriptor {
        let id: UUID
        let title: String
        let artist: String
        let album: String
        let tags: [String]
    }

    enum IntelligenceError: LocalizedError {
        case unavailable
        case noMatches

        var errorDescription: String? {
            switch self {
            case .unavailable: String(localized: "Apple Intelligence is not available on this device.")
            case .noMatches: String(localized: "No matching songs found. Try a different description.")
            }
        }
    }

    // Keep the prompt inside the model's context window.
    static let maxSongsPerRequest = 120

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    static func suggestPlaylist(prompt: String, songs: [SongDescriptor]) async throws -> (name: String, ids: [UUID]) {
        guard isAvailable else { throw IntelligenceError.unavailable }
        let candidates = Array(songs.prefix(maxSongsPerRequest))
        let list = candidates.enumerated().map { index, song -> String in
            var line = "\(index + 1). \(song.title) - \(song.artist.isEmpty ? "Unknown Artist" : song.artist)"
            if !song.album.isEmpty { line += " (album: \(song.album))" }
            if !song.tags.isEmpty { line += " [\(song.tags.joined(separator: ", "))]" }
            return line
        }.joined(separator: "\n")

        let session = LanguageModelSession(instructions: """
            You are the playlist curator inside Era, a personal offline music app. \
            The user describes a mood, theme or idea. You receive a numbered list of \
            songs from their library with artist, album and tags. Pick the songs that \
            fit the request best and invent a short playlist name. Only use numbers \
            from the list. Write the playlist name in the same language as the user's request.
            """)
        let response = try await session.respond(
            to: "Request: \(prompt)\n\nSongs:\n\(list)",
            generating: SmartPlaylistChoice.self)
        let choice = response.content
        let ids = choice.songNumbers.compactMap { number -> UUID? in
            let index = number - 1
            guard candidates.indices.contains(index) else { return nil }
            return candidates[index].id
        }
        let uniqueIDs = ids.reduce(into: (seen: Set<UUID>(), list: [UUID]())) { acc, id in
            if acc.seen.insert(id).inserted { acc.list.append(id) }
        }.list
        guard !uniqueIDs.isEmpty else { throw IntelligenceError.noMatches }
        let name = choice.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name.isEmpty ? String(localized: "Smart Playlist") : name, uniqueIDs)
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct SmartPlaylistChoice {
    @Guide(description: "A short, fitting playlist name, at most 4 words")
    var name: String
    @Guide(description: "The numbers of the songs from the list that fit the request")
    var songNumbers: [Int]
}
#endif
