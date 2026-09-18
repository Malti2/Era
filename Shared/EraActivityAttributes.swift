import Foundation
#if canImport(ActivityKit)
import ActivityKit

// Now Playing Live Activity: Lock Screen banner + Dynamic Island.
struct EraActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var songID: UUID
        public var title: String
        public var artist: String
        public var duration: Double
        public var position: Double      // playback seconds at referenceDate
        public var referenceDate: Date   // wall clock matching `position`
        public var rate: Float
        public var isPlaying: Bool
    }
    public var name: String
}
#endif
