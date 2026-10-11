import Foundation

/// Runtime box for `setOf(...)` / `mutableSetOf(...)`.
/// Stores unique elements in insertion order as runtime values.
final class RuntimeSetBox {
    /// Distinguishes the two live map-backed views this box can present.
    /// `.entries` materializes `MutableMap.MutableEntry` pair boxes on
    /// demand; `.keys` exposes the map's raw key values directly.
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
    /// KUU-1361: `NavigableSet.descendingSet()` shares a parent box —
    /// reads and mutations forward to it while iteration presents the
    /// elements reversed.
    private let viewParent: RuntimeSetBox?
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

    /// Marks the box as comparator-ordered (java.util.TreeSet). A `0` or
    /// `null`-sentinel comparator selects natural `Comparable` order;
    /// `invertCompare` flips the order for descending views.
    func enableSorted(comparatorRaw: Int, invertCompare: Bool = false) {
        sorted = true
        self.comparatorRaw = comparatorRaw == runtimeNullSentinelInt ? 0 : comparatorRaw
        self.invertCompare = invertCompare
    }

    /// Ordering used by sorted boxes: the stored `Comparator` object when
    /// one was supplied, else `Comparable` natural order. Descending views
    /// flip the sign.
    func sortedCompare(_ lhs: Int, _ rhs: Int) -> Int {
        let base = comparatorRaw != 0
            ? runtimeInvokeComparator(comparatorRaw, lhs, rhs)
            : runtimeCompareValues(lhs, rhs)
        return invertCompare ? -base : base
    }

    /// Binary search over sorted storage — the element's position when
    /// `found`, else the insertion index preserving comparator order.
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
                return viewParent.values.reversed()
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
        self.sorted = false
        self.comparatorRaw = 0
        self.invertCompare = false
    }

    /// `descendingSet()` view — delegates to the parent box while presenting
    /// elements reversed. Mutations write through, so the view and parent
    /// share contents.
    init(descendingViewOf parent: RuntimeSetBox) {
        self.storage = []
        self.index = [:]
        self.backingMapRaw = nil
        self.backingMapViewKind = .entries
        self.viewParent = parent
        self.sorted = true
        self.comparatorRaw = parent.comparatorRaw
        self.invertCompare = !parent.invertCompare
    }

    var count: Int {
        if let viewParent {
            return viewParent.count
        }
        if let backingMapRaw,
           let map = runtimeMapBox(from: backingMapRaw) {
            return map.count
        }
        return storage.count
    }

    var isEmpty: Bool {
        if let viewParent {
            return viewParent.isEmpty
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

    /// O(1) indexed access for the insertion-ordered set storage.
    subscript(index: Int) -> Int {
        guard let value = rawValue(at: index) else {
            preconditionFailure("RuntimeSetBox index out of bounds: \(index)")
        }
        return value
    }

    /// Returns an element in insertion order without materializing the set.
    /// Map-entry views retain their existing materialized entry representation.
    func rawValue(at index: Int) -> Int? {
        if let viewParent {
            guard index >= 0, index < viewParent.count else {
                return nil
            }
            return viewParent.rawValue(at: viewParent.count - 1 - index)
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
            return viewParent.contains(rawValue: rawValue)
        }
        if let backingMapRaw,
           let map = runtimeMapBox(from: backingMapRaw) {
            switch backingMapViewKind {
            case .entries:
                guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue),
                      let entry = tryCast(pointer, to: RuntimePairBox.self),
                      entry.mutableMapRaw == backingMapRaw,
                      let index = map.index(ofRawKey: entry.mutableMapKey),
                      let currentValue = map.rawValue(at: index)
                else {
                    return false
                }
                return runtimeValuesEqual(entry.secondValue, RuntimeValue(raw: currentValue))
            case .keys:
                return map.index(ofRawKey: rawValue) != nil
            }
        }
        if sorted {
            return sortedSearch(for: rawValue).found
        }
        return index[RuntimeElementKey(value: rawValue)] != nil
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
            return viewParent.remove(rawValue: rawValue)
        }
        if let backingMapRaw {
            guard !isEffectivelyReadOnly, let map = runtimeMapBox(from: backingMapRaw) else {
                return false
            }
            switch backingMapViewKind {
            case .entries:
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
            return viewParent.removeAll(keepingCapacity: keepingCapacity)
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

// MARK: - RuntimeChildReferenceProviding conformances (ABI-004)
//
// These conformances enable the recursive BFS freeze in kk_freeze_object to
// traverse all reachable object references when freezing an object graph.
// Only types that store `Int` child handles need to conform.

extension RuntimeSetBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] { values.compactMap(\.childReferenceRawValue) }
}
