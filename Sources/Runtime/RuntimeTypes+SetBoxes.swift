import Foundation

final class RuntimeSetBox {
    enum MapViewKind {
        case entries
        case keys
    }

    private var storage: [RuntimeValue]
    private var index: [RuntimeElementKey: Int]
    /// Non-nil for the mutable `entries`/`keys` views returned by
    /// `MutableMap`. The view reads/writes through to the destination map
    /// on every access (including iterator removal) instead of
    /// materializing a disconnected snapshot.
    private let backingMapRaw: Int?
    private let backingMapViewKind: MapViewKind
    private let viewParent: RuntimeSetBox?
    private let rangeView: RuntimeSortedRange?
    private let rangeBounds: RuntimeSortedBounds?
    private let isDescendingView: Bool
    /// KUU-1361: java.util.TreeSet ordering — `sorted` selects comparator
    /// order over insertion order, `comparatorRaw` holds the user
    /// `Comparator` object (0 = natural `Comparable` order), and
    /// `invertCompare` flips it for descending views.
    private(set) var sorted: Bool
    private(set) var comparatorRaw: Int
    private(set) var invertCompare: Bool
    private(set) var isReadOnly = false
    private var directModCount: Int = 0

    /// Structural-modification counter. An entries view has no storage of
    /// its own, so it forwards to the backing map's counter.
    var modCount: Int {
        if let viewParent {
            return viewParent.modCount
        }
        if let backingMapRaw, let map = runtimeMapBox(from: backingMapRaw) {
            return map.modCount
        }
        return directModCount
    }

    func enableSorted(comparatorRaw: Int, invertCompare: Bool = false) {
        sorted = true
        self.comparatorRaw = comparatorRaw == runtimeNullSentinelInt ? 0 : comparatorRaw
        self.invertCompare = invertCompare
    }

    func sortedCompare(_ lhs: Int, _ rhs: Int) -> Int {
        let base = comparatorRaw != 0
            ? runtimeInvokeComparator(comparatorRaw, lhs, rhs)
            : runtimeCompareValues(lhs, rhs)
        return invertCompare ? -base : base
    }

    private func sortedSearch(for rawValue: Int) -> (found: Bool, index: Int) {
        var low = 0
        var high = storage.count - 1
        while low <= high {
            let mid = low + (high - low) / 2
            let comparison = sortedCompare(storage[mid].legacyRawValue, rawValue)
            if comparison < 0 {
                low = mid + 1
            } else if comparison > 0 {
                high = mid - 1
            } else {
                return (true, mid)
            }
        }
        return (false, low)
    }

    var values: [RuntimeValue] {
        get {
            if let viewParent {
                var viewValues = viewParent.values
                if isDescendingView { viewValues.reverse() }
                guard let rangeView else { return viewValues }
                return viewValues.filter {
                    rangeView.contains($0.legacyRawValue, using: sortedCompare)
                }
            }
            if let backingMapRaw,
               let map = runtimeMapBox(from: backingMapRaw) {
                switch backingMapViewKind {
                case .entries:
                    return zip(map.keyValues, map.entryValues).map { key, value in
                        RuntimeValue(raw: runtimeMutableMapEntryNew(
                            mapRaw: backingMapRaw,
                            key: key,
                            value: value
                        ))
                    }
                case .keys:
                    return map.keyValues
                }
            }
            return storage
        }
        set {
            guard viewParent == nil, backingMapRaw == nil, !isReadOnly else { return }
            storage = newValue
            if sorted {
                storage.sort { sortedCompare($0.legacyRawValue, $1.legacyRawValue) < 0 }
            }
            rebuildIndex()
        }
    }

    var elements: [Int] {
        get {
            values.map(\.legacyRawValue)
        }
        set {
            guard viewParent == nil, backingMapRaw == nil, !isReadOnly else { return }
            storage = newValue.map { RuntimeValue(raw: $0) }
            if sorted {
                storage.sort { sortedCompare($0.legacyRawValue, $1.legacyRawValue) < 0 }
            }
            rebuildIndex()
        }
    }

    init(elements: [Int]) {
        self.storage = elements.map { RuntimeValue(raw: $0) }
        self.index = [:]
        self.backingMapRaw = nil
        self.backingMapViewKind = .entries
        self.viewParent = nil
        self.rangeView = nil
        self.rangeBounds = nil
        self.isDescendingView = false
        self.sorted = false
        self.comparatorRaw = 0
        self.invertCompare = false
        rebuildIndex()
    }

    init(values: [RuntimeValue]) {
        self.storage = values
        self.index = [:]
        self.backingMapRaw = nil
        self.backingMapViewKind = .entries
        self.viewParent = nil
        self.rangeView = nil
        self.rangeBounds = nil
        self.isDescendingView = false
        self.sorted = false
        self.comparatorRaw = 0
        self.invertCompare = false
        rebuildIndex()
    }

    init(mapEntriesOf mapRaw: Int) {
        self.storage = []
        self.index = [:]
        self.backingMapRaw = mapRaw
        self.backingMapViewKind = .entries
        self.viewParent = nil
        self.rangeView = nil
        self.rangeBounds = nil
        self.isDescendingView = false
        self.sorted = false
        self.comparatorRaw = 0
        self.invertCompare = false
    }

    init(mapKeysOf mapRaw: Int) {
        self.storage = []
        self.index = [:]
        self.backingMapRaw = mapRaw
        self.backingMapViewKind = .keys
        self.viewParent = nil
        self.rangeView = nil
        self.rangeBounds = nil
        self.isDescendingView = false
        self.sorted = false
        self.comparatorRaw = 0
        self.invertCompare = false
    }

    init(descendingViewOf parent: RuntimeSetBox) {
        self.storage = []
        self.index = [:]
        self.backingMapRaw = nil
        self.backingMapViewKind = .entries
        self.viewParent = parent
        self.rangeView = nil
        self.rangeBounds = parent.rangeBounds?.reversed()
        self.isDescendingView = true
        self.sorted = true
        self.comparatorRaw = parent.comparatorRaw
        self.invertCompare = !parent.invertCompare
    }

    init(rangeViewOf parent: RuntimeSetBox, range: RuntimeSortedRange) {
        self.storage = []
        self.index = [:]
        self.backingMapRaw = nil
        self.backingMapViewKind = .entries
        self.viewParent = parent
        self.rangeView = range
        self.rangeBounds = parent.rangeBounds?.intersecting(range, using: parent.sortedCompare)
            ?? RuntimeSortedBounds(range)
        self.isDescendingView = false
        self.sorted = true
        self.comparatorRaw = parent.comparatorRaw
        self.invertCompare = parent.invertCompare
    }

    var count: Int {
        if let viewParent {
            return values.count
        }
        if let backingMapRaw,
           let map = runtimeMapBox(from: backingMapRaw) {
            return map.count
        }
        return storage.count
    }

    var isEmpty: Bool {
        if let viewParent {
            return values.isEmpty
        }
        if let backingMapRaw,
           let map = runtimeMapBox(from: backingMapRaw) {
            return map.isEmpty
        }
        return storage.isEmpty
    }

    var indices: Range<Int> {
        0..<count
    }

    subscript(index: Int) -> Int {
        guard let value = rawValue(at: index) else {
            preconditionFailure("RuntimeSetBox index out of bounds: \(index)")
        }
        return value
    }

    /// Returns an element in the set's current iteration order.
    func rawValue(at index: Int) -> Int? {
        if let viewParent {
            guard values.indices.contains(index) else { return nil }
            return values[index].legacyRawValue
        }
        if let backingMapRaw,
           let map = runtimeMapBox(from: backingMapRaw) {
            switch backingMapViewKind {
            case .entries:
                guard map.keys.indices.contains(index), map.values.indices.contains(index) else {
                    return nil
                }
                return runtimeMutableMapEntryNew(
                    mapRaw: backingMapRaw,
                    key: map.keys[index],
                    value: map.values[index]
                )
            case .keys:
                guard map.keys.indices.contains(index) else {
                    return nil
                }
                return map.keys[index]
            }
        }
        guard storage.indices.contains(index) else {
            return nil
        }
        return storage[index].legacyRawValue
    }

    func contains(rawValue: Int) -> Bool {
        if let viewParent {
            return isWithinView(rawValue) && viewParent.contains(rawValue: rawValue)
        }
        if let backingMapRaw,
           let map = runtimeMapBox(from: backingMapRaw) {
            switch backingMapViewKind {
            case .entries:
                if map.usesReferenceEquality {
                    guard let entry = runtimeIdentityMapEntryValues(rawValue),
                          let index = map.index(ofRawKey: entry.key),
                          let value = map.rawValue(at: index) else { return false }
                    return value == entry.value
                }
                guard let entry = runtimeMapEntryValues(rawValue: rawValue) ?? runtimeSourceMapEntryValues(rawValue),
                      let index = map.index(ofRawKey: entry.key),
                      let currentValue = map.rawValue(at: index)
                else {
                    return false
                }
                return runtimeLookupValuesEqual(entry.value, currentValue)
            case .keys:
                return map.index(ofRawKey: rawValue) != nil
            }
        }
        if sorted {
            return sortedSearch(for: rawValue).found
        }
        return index[RuntimeElementKey(value: rawValue)] != nil
    }

    var usesReferenceEquality: Bool {
        if let viewParent { return viewParent.usesReferenceEquality }
        return backingMapRaw.flatMap { runtimeMapBox(from: $0) }?.usesReferenceEquality == true
    }

    func elementHash(_ raw: Int) -> Int {
        if usesReferenceEquality, backingMapViewKind == .keys {
            return kk_native_identityHashCode(raw)
        }
        return runtimeValueHash(raw)
    }

    var isEffectivelyReadOnly: Bool {
        if let viewParent {
            return viewParent.isEffectivelyReadOnly
        }
        if let backingMapRaw,
           let map = runtimeMapBox(from: backingMapRaw) {
            return map.isEffectivelyReadOnly
        }
        return isReadOnly
    }

    @discardableResult
    func insert(rawValue: Int) -> Bool {
        insert(value: RuntimeValue(raw: rawValue))
    }

    @discardableResult
    func insert(value: RuntimeValue) -> Bool {
        if let viewParent {
            guard isWithinView(value.legacyRawValue) else { return false }
            return viewParent.insert(value: value)
        }
        guard backingMapRaw == nil, !isReadOnly else { return false }
        if sorted {
            let position = sortedSearch(for: value.legacyRawValue)
            guard !position.found else {
                return false
            }
            storage.insert(value, at: position.index)
            directModCount += 1
            return true
        }
        let key = RuntimeElementKey(runtimeValue: value)
        guard index[key] == nil else {
            return false
        }
        let newIndex = storage.count
        storage.append(value)
        index[key] = newIndex
        directModCount += 1
        return true
    }

    @discardableResult
    func remove(rawValue: Int) -> Bool {
        if let viewParent {
            guard isWithinView(rawValue) else { return false }
            return viewParent.remove(rawValue: rawValue)
        }
        if let backingMapRaw {
            guard !isEffectivelyReadOnly, let map = runtimeMapBox(from: backingMapRaw) else {
                return false
            }
            switch backingMapViewKind {
            case .entries:
                if map.usesReferenceEquality {
                    guard let entry = runtimeIdentityMapEntryValues(rawValue),
                          let index = map.index(ofRawKey: entry.key),
                          let value = map.rawValue(at: index),
                          value == entry.value else { return false }
                    _ = map.remove(key: entry.key)
                    return true
                }
                guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue),
                      let entry = tryCast(pointer, to: RuntimePairBox.self),
                      entry.mutableMapRaw == backingMapRaw,
                      map.index(ofRawKey: entry.mutableMapKey) != nil
                else {
                    return false
                }
                _ = map.remove(key: entry.mutableMapKey)
                return true
            case .keys:
                guard map.index(ofRawKey: rawValue) != nil else {
                    return false
                }
                _ = map.remove(key: rawValue)
                return true
            }
        }
        if sorted {
            guard !isReadOnly else { return false }
            let position = sortedSearch(for: rawValue)
            guard position.found else {
                return false
            }
            storage.remove(at: position.index)
            directModCount += 1
            return true
        }
        guard !isReadOnly, let index = index[RuntimeElementKey(value: rawValue)] else {
            return false
        }
        storage.remove(at: index)
        rebuildIndex()
        directModCount += 1
        return true
    }

    @discardableResult
    func removeAll(keepingCapacity: Bool = false) -> Bool {
        if let viewParent {
            var removed = false
            for value in values {
                removed = viewParent.remove(rawValue: value.legacyRawValue) || removed
            }
            return removed
        }
        if let backingMapRaw,
           let map = runtimeMapBox(from: backingMapRaw) {
            guard !map.isEffectivelyReadOnly else {
                return false
            }
            let hadElements = !map.isEmpty
            map.removeAll()
            return hadElements
        }
        guard !isReadOnly, !storage.isEmpty else {
            return false
        }
        storage.removeAll(keepingCapacity: keepingCapacity)
        index.removeAll(keepingCapacity: keepingCapacity)
        directModCount += 1
        return true
    }

    @discardableResult
    func removeAll(where shouldRemove: (RuntimeValue) throws -> Bool) rethrows -> Bool {
        guard !isEffectivelyReadOnly else {
            return false
        }
        if viewParent != nil {
            var removed = false
            for entry in values where try shouldRemove(entry) {
                removed = remove(rawValue: entry.legacyRawValue) || removed
            }
            return removed
        }
        if backingMapRaw != nil {
            var removed = false
            for entry in values where try shouldRemove(entry) {
                removed = remove(rawValue: entry.legacyRawValue) || removed
            }
            return removed
        }
        let originalCount = storage.count
        try storage.removeAll(where: shouldRemove)
        guard storage.count != originalCount else {
            return false
        }
        rebuildIndex()
        directModCount += 1
        return true
    }

    func acceptsInsertion(rawValue: Int) -> Bool {
        isWithinView(rawValue) && (viewParent?.acceptsInsertion(rawValue: rawValue) ?? true)
    }

    func acceptsRangeView(_ range: RuntimeSortedRange) -> Bool {
        if let lower = range.lowerBoundRaw, let upper = range.upperBoundRaw,
           sortedCompare(lower, upper) > 0 {
            return false
        }
        return rangeBounds?.acceptsRange(range, using: sortedCompare) ?? true
    }

    private func isWithinView(_ rawValue: Int) -> Bool {
        rangeView?.contains(rawValue, using: sortedCompare) ?? true
    }

    private func rebuildIndex() {
        guard !sorted else { return }
        index.removeAll(keepingCapacity: true)
        index.reserveCapacity(storage.count)
        for (offset, value) in storage.enumerated() {
            let key = RuntimeElementKey(runtimeValue: value)
            // Keep the first position for malformed duplicate input, matching
            // the legacy linear lookup behavior.
            if index[key] == nil {
                index[key] = offset
            }
        }
    }

    init(capacity: Int) {
        self.storage = []
        self.index = [:]
        self.backingMapRaw = nil
        self.backingMapViewKind = .entries
        self.viewParent = nil
        self.rangeView = nil
        self.rangeBounds = nil
        self.isDescendingView = false
        self.sorted = false
        self.comparatorRaw = 0
        self.invertCompare = false
        self.storage.reserveCapacity(max(0, capacity))
        self.index.reserveCapacity(max(0, capacity))
    }

    func freeze() {
        isReadOnly = true
    }
}

// These conformances enable the recursive BFS freeze in kk_freeze_object to
// traverse all reachable object references when freezing an object graph.
// Only types that store `Int` child handles need to conform.

extension RuntimeSetBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] { values.compactMap(\.childReferenceRawValue) }
}
