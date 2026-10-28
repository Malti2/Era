import Foundation

enum Reordering {
    /// Verschiebt die Elemente an `source` vor das Ziel `destination` (Indizes des
    /// Ausgangsarrays) - gleiche Semantik wie SwiftUIs `move(fromOffsets:toOffset:)`.
    static func move<T>(_ items: [T], from source: IndexSet, to destination: Int) -> [T] {
        let valid = source.filter { items.indices.contains($0) }
        guard !valid.isEmpty else { return items }
        let moved = valid.map { items[$0] }
        var rest = items.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let removedBefore = valid.filter { $0 < destination }.count
        let target = min(max(destination - removedBefore, 0), rest.count)
        rest.insert(contentsOf: moved, at: target)
        return rest
    }
}
