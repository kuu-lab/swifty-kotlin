import Foundation

/// Runtime box for `mapOf(...)` / `mutableMapOf(...)`.
/// Stores keys and values as parallel runtime-value arrays.
final class RuntimeMapBox {
    private var keyStorage: [RuntimeValue]
    private var valueStorage: [RuntimeValue]
    private let backingMap: RuntimeMapBox?
    private var keyIndex: [RuntimeElementKey: Int]
    let defaultValueFnPtr: Int
    let defaultValueClosureRaw: Int
    /// KUU-1361: java.util.TreeMap ordering — `sorted` selects comparator key
    /// order over insertion order, `comparatorRaw` holds the user
    /// `Comparator` object (0 = natural `Comparable` order), and
    /// `invertCompare` flips it for `descendingMap()` views.
    private(set) var sorted: Bool
    private(set) var comparatorRaw: Int
    private(set) var invertCompare: Bool
    private(set) var isReadOnly = false
    private var directModCount: Int = 0

    /// Marks the box as comparator-ordered (java.util.TreeMap). A `0` or
    /// `null`-sentinel comparator selects natural `Comparable` order;
    /// `invertCompare` flips the order for descending views.
    func enableSorted(comparatorRaw: Int, invertCompare: Bool = false) {
        sorted = true
        self.comparatorRaw = comparatorRaw == runtimeNullSentinelInt ? 0 : comparatorRaw
        self.invertCompare = invertCompare
    }

    /// Key ordering used by sorted boxes: the stored `Comparator` object
    /// when one was supplied, else `Comparable` natural order. Descending
    /// views flip the sign.
    func sortedCompare(_ lhs: Int, _ rhs: Int) -> Int {
        let base = comparatorRaw != 0
            ? runtimeInvokeComparator(comparatorRaw, lhs, rhs)
            : runtimeCompareValues(lhs, rhs)
        return invertCompare ? -base : base
    }

    /// Binary search over sorted key storage — the key's position when
    /// `found`, else the insertion index preserving comparator order.
    private func sortedKeySearch(for rawKey: Int) -> (found: Bool, index: Int) {
        var low = 0
        var high = keyStorage.count - 1
        while low <= high {
            let mid = low + (high - low) / 2
            let comparison = sortedCompare(keyStorage[mid].legacyRawValue, rawKey)
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

    var isEffectivelyReadOnly: Bool {
        backingMap?.isEffectivelyReadOnly ?? isReadOnly
    }

    /// Structural-modification counter. Bumped on key insertion/removal
    /// (`appendEntry`/`remove`/`removeAll`), never on `updateValue`, which
    /// only replaces an existing key's value (matches JVM `HashMap.put`'s
    /// non-structural update not incrementing `modCount`).
    var modCount: Int {
        backingMap?.modCount ?? directModCount
    }

    var keyValues: [RuntimeValue] {
        get {
            if let backingMap {
                return invertCompare ? backingMap.keyValues.reversed() : backingMap.keyValues
            }
            return keyStorage
        }
        set {
            if let backingMap {
                backingMap.keyValues = newValue
            } else {
                guard !isReadOnly else { return }
                keyStorage = newValue
                if sorted {
                    let pairs = zip(keyStorage, valueStorage)
                        .sorted { sortedCompare($0.0.legacyRawValue, $1.0.legacyRawValue) < 0 }
                    keyStorage = pairs.map(\.0)
                    valueStorage = pairs.map(\.1)
                }
                rebuildKeyIndex()
            }
        }
    }

    var entryValues: [RuntimeValue] {
        get {
            if let backingMap {
                return invertCompare ? backingMap.entryValues.reversed() : backingMap.entryValues
            }
            return valueStorage
        }
        set {
            if let backingMap {
                backingMap.entryValues = newValue
            } else {
                guard !isReadOnly else { return }
                valueStorage = newValue
            }
        }
    }

    var keys: [Int] {
        get {
            keyValues.map(\.legacyRawValue)
        }
        set {
            keyValues = newValue.map { RuntimeValue(raw: $0) }
        }
    }

    var values: [Int] {
        get {
            entryValues.map(\.legacyRawValue)
        }
        set {
            entryValues = newValue.map { RuntimeValue(raw: $0) }
        }
    }

    init(
        keys: [Int],
        values: [Int],
        defaultValueFnPtr: Int = 0,
        defaultValueClosureRaw: Int = 0,
        backingMap: RuntimeMapBox? = nil
    ) {
        self.keyStorage = keys.map { RuntimeValue(raw: $0) }
        self.valueStorage = values.map { RuntimeValue(raw: $0) }
        self.backingMap = backingMap
        self.keyIndex = [:]
        self.defaultValueFnPtr = defaultValueFnPtr
        self.defaultValueClosureRaw = defaultValueClosureRaw
        self.sorted = false
        self.comparatorRaw = 0
        self.invertCompare = false
        rebuildKeyIndex()
    }

    /// `descendingMap()` view — delegates reads and mutations to the parent
    /// box while `invertCompare` reverses key/entry presentation.
    init(descendingViewOf parent: RuntimeMapBox) {
        self.keyStorage = []
        self.valueStorage = []
        self.backingMap = parent
        self.keyIndex = [:]
        self.defaultValueFnPtr = 0
        self.defaultValueClosureRaw = 0
        self.sorted = true
        self.comparatorRaw = parent.comparatorRaw
        self.invertCompare = !parent.invertCompare
    }

    var count: Int {
        backingMap?.count ?? keyStorage.count
    }

    var isEmpty: Bool {
        backingMap?.isEmpty ?? keyStorage.isEmpty
    }

    func index(ofRawKey key: Int) -> Int? {
        if let backingMap {
            return backingMap.index(ofRawKey: key)
        }
        if sorted {
            let position = sortedKeySearch(for: key)
            return position.found ? position.index : nil
        }
        return keyIndex[RuntimeElementKey(value: key)]
    }

    func rawValue(at index: Int) -> Int? {
        if let backingMap {
            return backingMap.rawValue(at: index)
        }
        guard valueStorage.indices.contains(index) else {
            return nil
        }
        return valueStorage[index].legacyRawValue
    }

    func runtimeValue(at index: Int) -> RuntimeValue? {
        if let backingMap {
            return backingMap.runtimeValue(at: index)
        }
        guard valueStorage.indices.contains(index) else {
            return nil
        }
        return valueStorage[index]
    }

    func updateValue(at index: Int, rawValue: Int) {
        updateValue(at: index, value: RuntimeValue(raw: rawValue))
    }

    func updateValue(at index: Int, value: RuntimeValue) {
        if let backingMap {
            backingMap.updateValue(at: index, value: value)
            return
        }
        guard !isReadOnly else { return }
        guard valueStorage.indices.contains(index) else {
            valueStorage.append(value)
            return
        }
        valueStorage[index] = value
    }

    func appendEntry(key: Int, value: Int) {
        appendEntry(key: RuntimeValue(raw: key), value: RuntimeValue(raw: value))
    }

    func appendEntry(key: RuntimeValue, value: RuntimeValue) {
        if let backingMap {
            backingMap.appendEntry(key: key, value: value)
            return
        }
        guard !isReadOnly else { return }
        if sorted {
            let position = sortedKeySearch(for: key.legacyRawValue)
            if position.found {
                updateValue(at: position.index, value: value)
                return
            }
            keyStorage.insert(key, at: position.index)
            valueStorage.insert(value, at: position.index)
            directModCount += 1
            return
        }
        let newIndex = keyStorage.count
        keyStorage.append(key)
        valueStorage.append(value)
        let runtimeKey = RuntimeElementKey(runtimeValue: key)
        if keyIndex[runtimeKey] == nil {
            keyIndex[runtimeKey] = newIndex
        }
        directModCount += 1
    }

    @discardableResult
    func put(key: Int, value: Int) -> Int? {
        put(key: RuntimeValue(raw: key), value: RuntimeValue(raw: value))?.legacyRawValue
    }

    @discardableResult
    func put(key: RuntimeValue, value: RuntimeValue) -> RuntimeValue? {
        if let backingMap {
            return backingMap.put(key: key, value: value)
        }
        guard !isReadOnly else { return nil }
        if sorted {
            let position = sortedKeySearch(for: key.legacyRawValue)
            if position.found {
                let previous = runtimeValue(at: position.index)
                updateValue(at: position.index, value: value)
                return previous
            }
            keyStorage.insert(key, at: position.index)
            valueStorage.insert(value, at: position.index)
            directModCount += 1
            return nil
        }
        let runtimeKey = RuntimeElementKey(runtimeValue: key)
        if let index = keyIndex[runtimeKey] {
            let previous = runtimeValue(at: index)
            updateValue(at: index, value: value)
            return previous
        }
        appendEntry(key: key, value: value)
        return nil
    }

    @discardableResult
    func remove(key: Int) -> Int? {
        if let backingMap {
            return backingMap.remove(key: key)
        }
        guard !isReadOnly, let index = index(ofRawKey: key) else {
            return nil
        }
        keyStorage.remove(at: index)
        let removedValue = valueStorage.indices.contains(index) ? valueStorage.remove(at: index).legacyRawValue : nil
        rebuildKeyIndex()
        directModCount += 1
        return removedValue
    }

    func removeAll() {
        if let backingMap {
            backingMap.removeAll()
            return
        }
        guard !isReadOnly else { return }
        keyStorage.removeAll()
        valueStorage.removeAll()
        keyIndex.removeAll()
        directModCount += 1
    }

    private func rebuildKeyIndex() {
        guard !sorted else { return }
        keyIndex.removeAll(keepingCapacity: true)
        keyIndex.reserveCapacity(keyStorage.count)
        for (offset, key) in keyStorage.enumerated() {
            let runtimeKey = RuntimeElementKey(runtimeValue: key)
            // Keep the first position for malformed duplicate input, matching
            // the legacy linear lookup behavior.
            if keyIndex[runtimeKey] == nil {
                keyIndex[runtimeKey] = offset
            }
        }
    }

    init(capacity: Int, defaultValueFnPtr: Int = 0, defaultValueClosureRaw: Int = 0) {
        self.keyStorage = []
        self.valueStorage = []
        self.backingMap = nil
        self.keyIndex = [:]
        self.keyStorage.reserveCapacity(max(0, capacity))
        self.valueStorage.reserveCapacity(max(0, capacity))
        self.keyIndex.reserveCapacity(max(0, capacity))
        self.defaultValueFnPtr = defaultValueFnPtr
        self.defaultValueClosureRaw = defaultValueClosureRaw
        self.sorted = false
        self.comparatorRaw = 0
        self.invertCompare = false
    }

    func freeze() {
        isReadOnly = true
    }
}

/// Iterator box for `Map` iteration via `for (entry in map)`. Read-only (no
/// `remove()`), but the for-loop lowering resolves `for ((k, _) in map)` to
/// this same iterator even when `map` is a `MutableMap`, so it still needs
/// its own comodification check — mutating the map through a different
/// handle (`map[key] = value`, `map.remove(...)`) while this iterator is
/// live must still throw `ConcurrentModificationException`.
final class RuntimeMapIteratorBox {
    let mapRaw: Int
    let keys: [Int]
    let values: [Int]
    var index: Int
    var expectedModCount: Int

    init(mapRaw: Int, keys: [Int], values: [Int]) {
        self.mapRaw = mapRaw
        self.keys = keys
        self.values = values
        index = 0
        expectedModCount = runtimeMapBox(from: mapRaw)?.modCount ?? 0
    }

    func isInSyncWithBackingMap() -> Bool {
        guard let map = runtimeMapBox(from: mapRaw) else { return true }
        return map.modCount == expectedModCount
    }
}

/// MutableMap iterator whose entries remain connected to the destination map.
final class RuntimeMutableMapIteratorBox {
    let mapRaw: Int
    let keys: [Int]
    var index: Int
    var lastKey: Int?
    /// The backing map's `modCount` as of the last point this iterator
    /// observed it in sync (construction, or its own successful `remove()`,
    /// which re-syncs after performing the mutation).
    var expectedModCount: Int

    init(mapRaw: Int, keys: [Int]) {
        self.mapRaw = mapRaw
        self.keys = keys
        index = 0
        lastKey = nil
        expectedModCount = runtimeMapBox(from: mapRaw)?.modCount ?? 0
    }

    /// `true` when the backing map has not structurally changed since this
    /// iterator last observed it.
    func isInSyncWithBackingMap() -> Bool {
        guard let map = runtimeMapBox(from: mapRaw) else { return true }
        return map.modCount == expectedModCount
    }
}

// MARK: - RuntimeChildReferenceProviding conformances (ABI-004)
//
// These conformances enable the recursive BFS freeze in kk_freeze_object to
// traverse all reachable object references when freezing an object graph.
// Only types that store `Int` child handles need to conform.

extension RuntimeMapBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] {
        keyValues.compactMap(\.childReferenceRawValue)
            + entryValues.compactMap(\.childReferenceRawValue)
    }
}

extension RuntimeMutableMapIteratorBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] { mapRaw == 0 ? [] : [mapRaw] }
}
