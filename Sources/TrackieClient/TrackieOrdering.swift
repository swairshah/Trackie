import Foundation

public extension Array where Element == TrackieItem {
    @discardableResult
    mutating func moveItems(withStatus status: TrackieStatus, from source: IndexSet, to destination: Int) -> Bool {
        let matchingIndices = indices.filter { self[$0].status == status }
        let sourceOffsets = source.filter { matchingIndices.indices.contains($0) }
        guard !sourceOffsets.isEmpty else { return false }

        var matchingItems = matchingIndices.map { self[$0] }
        let originalMatchingItems = matchingItems
        matchingItems.moveElements(fromOffsets: sourceOffsets, toOffset: destination)
        guard matchingItems != originalMatchingItems else { return false }

        for (index, item) in zip(matchingIndices, matchingItems) {
            self[index] = item
        }
        return true
    }
}

private extension Array {
    mutating func moveElements(fromOffsets sourceOffsets: [Int], toOffset destination: Int) {
        let sourceSet = Set(sourceOffsets)
        let movingElements = sourceOffsets.sorted().map { self[$0] }
        var remainingElements = enumerated()
            .filter { !sourceSet.contains($0.offset) }
            .map(\.element)

        let removedBeforeDestination = sourceOffsets.filter { $0 < destination }.count
        let adjustedDestination = destination - removedBeforeDestination
        let insertionIndex = Swift.max(0, Swift.min(adjustedDestination, remainingElements.count))

        remainingElements.insert(contentsOf: movingElements, at: insertionIndex)
        self = remainingElements
    }
}
