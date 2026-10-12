import Foundation

// MARK: - Collection Types (STDLIB-001)

/// Runtime box for `listOf(...)` / `mutableListOf(...)`.
/// Stores elements directly or as a lightweight view over another list/array.
final class RuntimeListBox {
    private final class DirectStorage {
        var values: [RuntimeValue]
        /// Bumped on every structural mutation (size change), never on an
        /// element replacement. Iterators capture this at creation and
        /// re-check it in `next()` to detect concurrent modification.
        var modCount: Int = 0

        init(values: [RuntimeValue]) {
            self.values = values
        }
    }

    private enum Storage {
        case direct(DirectStorage)
        case reversedViewOf(RuntimeListBox)
        case arrayViewOf(RuntimeArrayBox, RuntimePrimitiveArrayElementKind?)
        case dequeViewOf(RuntimeArrayDequeBox)
        case subList(RuntimeListSlice)
        /// Live view for `MutableMap.values`: reads the backing map's
        /// values on every access instead of a disconnected snapshot.
        /// Only single-index removal (via `removeMapBackedValue(at:)`) is
        /// supported as a write path, matching the real Kotlin
        /// `MutableCollection<V>` surface exposed for `.values` (no
        /// positional insert/set).
        case mapValuesViewOf(Int)
    }

    private var storage: Storage
    private(set) var isReadOnly = false

    var isEffectivelyReadOnly: Bool {
        if isReadOnly { return true }
        switch storage {
        case .direct, .arrayViewOf, .dequeViewOf:
            return false
        case .reversedViewOf(let base):
            return base.isEffectivelyReadOnly
        case .subList(let slice):
            return slice.base.isEffectivelyReadOnly
        case .mapValuesViewOf(let mapRaw):
            return runtimeMapBox(from: mapRaw)?.isEffectivelyReadOnly ?? false
        }
    }

    init(elements: [Int]) {
        storage = .direct(DirectStorage(values: elements.map { RuntimeValue(raw: $0) }))
    }

    init(values: [RuntimeValue]) {
        storage = .direct(DirectStorage(values: values))
    }

    init(capacity: Int) {
        var values: [RuntimeValue] = []
        values.reserveCapacity(max(0, capacity))
        storage = .direct(DirectStorage(values: values))
    }

    init(reversedViewOf base: RuntimeListBox) {
        storage = .reversedViewOf(base)
    }

    init(arrayViewOf base: RuntimeArrayBox, elementKind: RuntimePrimitiveArrayElementKind? = nil) {
        storage = .arrayViewOf(base, elementKind)
    }

    // Primitive arrays store raw words; generic list consumers require boxed values.
    private func arrayViewValue(_ value: RuntimeValue, kind: RuntimePrimitiveArrayElementKind?) -> RuntimeValue {
        guard let kind else { return value }
        let raw = value.legacyRawValue
        switch kind {
        case .boolean: return RuntimeValue(raw: kk_box_bool(raw))
        case .char: return RuntimeValue(raw: kk_box_char(raw))
        case .float: return RuntimeValue(raw: kk_box_float(raw))
        case .double: return RuntimeValue(raw: kk_box_double_nonnull(raw))
        case .long: return RuntimeValue(raw: kk_box_long_nonnull(raw))
        default: return value
        }
    }

    private func arrayStorageValue(_ value: RuntimeValue, kind: RuntimePrimitiveArrayElementKind?) -> RuntimeValue {
        guard let kind else { return value }
        let raw = runtimeCollectionABIValue(value)
        switch kind {
        case .boolean: return RuntimeValue(raw: kk_unbox_bool_static(raw))
        case .char: return RuntimeValue(raw: kk_unbox_char_static(raw))
        case .float: return RuntimeValue(raw: kk_unbox_float_static(raw))
        case .double: return RuntimeValue(raw: kk_unbox_double_nonnull_static(raw))
        case .long: return RuntimeValue(raw: kk_unbox_long(raw))
        default: return value
        }
    }

    init(dequeViewOf base: RuntimeArrayDequeBox) {
        storage = .dequeViewOf(base)
    }

    init(subListOf base: RuntimeListBox, fromIndex: Int, toIndex: Int) {
        storage = .subList(RuntimeListSlice(base: base, fromIndex: fromIndex, toIndex: toIndex))
    }

    init(mapValuesOf mapRaw: Int) {
        storage = .mapValuesViewOf(mapRaw)
    }

    var values: [RuntimeValue] {
        get {
            switch storage {
            case .direct(let direct):
                return direct.values
            case .reversedViewOf(let base):
                return Array(base.values.reversed())
            case .arrayViewOf(let base, let kind):
                return kind == nil ? base.values : base.values.map { arrayViewValue($0, kind: kind) }
            case .dequeViewOf(let base):
                return base.values
            case .subList(let slice):
                return Array(slice.base.values[slice.fromIndex..<slice.toIndex])
            case .mapValuesViewOf(let mapRaw):
                return runtimeMapBox(from: mapRaw)?.entryValues ?? []
            }
        }
        set {
            guard !isEffectivelyReadOnly else { return }
            switch storage {
            case .direct(let direct):
                if newValue.count != direct.values.count {
                    direct.modCount += 1
                }
                direct.values = newValue
            case .reversedViewOf(let base):
                base.values = Array(newValue.reversed())
            case .arrayViewOf(let base, let kind):
                base.values = kind == nil ? newValue : newValue.map { arrayStorageValue($0, kind: kind) }
            case .dequeViewOf(let base):
                base.values = newValue
            case .subList(let slice):
                var baseValues = slice.base.values
                baseValues.replaceSubrange(slice.fromIndex..<slice.toIndex, with: newValue)
                slice.toIndex = slice.fromIndex + newValue.count
                slice.base.values = baseValues
                slice.expectedModCount = slice.base.modCount
            case .mapValuesViewOf(let mapRaw):
                // `MutableCollection<V>` exposes no positional replace for
                // `.values`; only a full clear (matching `.clear()`) is a
                // meaningful whole-array assignment here.
                guard newValue.isEmpty,
                      let map = runtimeMapBox(from: mapRaw),
                      !map.isEffectivelyReadOnly
                else { return }
                map.removeAll()
            }
        }
    }

    /// Structural-modification counter (Java/Kotlin `modCount` equivalent).
    /// View storages forward to the backing list's own counter, so an
    /// iterator over a `subList`/reversed view still detects a structural
    /// change made through the root list.
    var modCount: Int {
        switch storage {
        case .direct(let direct):
            return direct.modCount
        case .reversedViewOf(let base):
            return base.modCount
        case .arrayViewOf:
            return 0
        case .dequeViewOf(let base):
            return base.modCount
        case .subList(let slice):
            return slice.base.modCount
        case .mapValuesViewOf(let mapRaw):
            return runtimeMapBox(from: mapRaw)?.modCount ?? 0
        }
    }

    var isValidView: Bool {
        switch storage {
        case .subList(let slice):
            return slice.expectedModCount == slice.base.modCount && slice.base.isValidView
        case .reversedViewOf(let base):
            return base.isValidView
        case .direct, .arrayViewOf, .dequeViewOf, .mapValuesViewOf:
            return true
        }
    }

    func freeze() {
        isReadOnly = true
    }

    var count: Int {
        switch storage {
        case .direct(let direct):
            return direct.values.count
        case .reversedViewOf(let base):
            return base.count
        case .arrayViewOf(let base, _):
            return base.count
        case .dequeViewOf(let base):
            return base.count
        case .subList(let slice):
            return slice.toIndex - slice.fromIndex
        case .mapValuesViewOf(let mapRaw):
            return runtimeMapBox(from: mapRaw)?.count ?? 0
        }
    }

    var indices: Range<Int> {
        0..<count
    }

    func value(at index: Int) -> RuntimeValue {
        switch storage {
        case .direct(let direct):
            return direct.values[index]
        case .reversedViewOf(let base):
            return base.value(at: base.count - 1 - index)
        case .arrayViewOf(let base, let kind):
            return arrayViewValue(base.values[index], kind: kind)
        case .dequeViewOf(let base):
            return base.element(at: index)!
        case .subList(let slice):
            return slice.base.value(at: slice.fromIndex + index)
        case .mapValuesViewOf(let mapRaw):
            return runtimeMapBox(from: mapRaw)?.entryValues[index] ?? RuntimeValue(raw: 0)
        }
    }

    /// O(1) single-element access. Prefer this over `elements[index]` because
    /// `elements` materializes the whole list on every get/set.
    subscript(index: Int) -> Int {
        get {
            runtimeCollectionABIValue(value(at: index))
        }
        set {
            guard !isEffectivelyReadOnly else { return }
            switch storage {
            case .direct(let direct):
                direct.values[index] = RuntimeValue(
                    raw: newValue,
                    anyFallbackTag: direct.values[index].anyFallbackTag
                )
            case .reversedViewOf(let base):
                base[base.count - 1 - index] = newValue
            case .arrayViewOf(let base, let kind):
                base[index] = arrayStorageValue(RuntimeValue(raw: newValue), kind: kind).legacyRawValue
            case .dequeViewOf(let base):
                let previous = base.element(at: index)!
                base.setValue(RuntimeValue(raw: newValue, anyFallbackTag: previous.anyFallbackTag), at: index)
            case .subList(let slice):
                slice.base[slice.fromIndex + index] = newValue
            case .mapValuesViewOf:
                // `MutableCollection<V>` has no indexed `set` for `.values`;
                // unreachable through valid Kotlin code.
                break
            }
        }
    }

    /// Stores an already-tagged value without materializing the surrounding collection.
    func setValue(_ value: RuntimeValue, at index: Int) {
        guard !isEffectivelyReadOnly else { return }
        switch storage {
        case .direct(let direct):
            direct.values[index] = runtimeValuePreservingAnyFallbackTag(
                value,
                existing: direct.values[index]
            )
        case .reversedViewOf(let base):
            base.setValue(value, at: base.count - 1 - index)
        case .arrayViewOf(let base, let kind):
            base.setValue(arrayStorageValue(value, kind: kind), at: index)
        case .dequeViewOf(let base):
            base.setValue(value, at: index)
        case .subList(let slice):
            slice.base.setValue(value, at: slice.fromIndex + index)
        case .mapValuesViewOf:
            // Unreachable: see the subscript setter above.
            break
        }
    }

    /// Runs `body` on the backing array and returns its result. For `.direct`
    /// storage the mutation goes through `direct.values`, so the buffer is
    /// appended/removed in place when uniquely referenced instead of being
    /// copied on every call; a buffer still shared with a snapshot (e.g. an
    /// iterator's captured `values`) copy-on-writes inside `body` as usual.
    /// View-backed storage keeps the materialize–mutate–write-back
    /// semantics of the `values` setter, and a read-only list still drops
    /// the write-back.
    @discardableResult
    func withMutableValues<R>(_ body: (inout [RuntimeValue]) -> R) -> R {
        guard !isEffectivelyReadOnly else {
            var values = values
            return body(&values)
        }
        switch storage {
        case .direct(let direct):
            let countBefore = direct.values.count
            let result = body(&direct.values)
            if direct.values.count != countBefore {
                direct.modCount += 1
            }
            return result
        case .reversedViewOf, .arrayViewOf, .dequeViewOf, .subList:
            var values = self.values
            let result = body(&values)
            self.values = values
            return result
        case .mapValuesViewOf:
            // Structural edits aren't reachable through the real Kotlin
            // `MutableCollection<V>` surface exposed for `.values` (no
            // positional insert, and removal goes through
            // `removeMapBackedValue(at:)` so the backing map's key stays
            // aligned by index). Materialize-and-discard here so an
            // unexpected caller can't desync the key/value arrays.
            var values = self.values
            return body(&values)
        }
    }

    /// True when this list is the live view returned by `MutableMap.values`.
    var isMapValuesView: Bool {
        if case .mapValuesViewOf = storage { return true }
        return false
    }

    /// Removes the backing map's key/value pair at `index` (as seen through
    /// this values view). Only valid when `isMapValuesView` is true.
    @discardableResult
    func removeMapBackedValue(at index: Int) -> Bool {
        guard case let .mapValuesViewOf(mapRaw) = storage,
              let map = runtimeMapBox(from: mapRaw),
              !map.isEffectivelyReadOnly,
              map.keys.indices.contains(index)
        else {
            return false
        }
        let key = map.keys[index]
        guard map.index(ofRawKey: key) != nil else {
            return false
        }
        _ = map.remove(key: key)
        return true
    }

    var elements: [Int] {
        get {
            values.map(\.legacyRawValue)
        }
        set {
            values = newValue.map { RuntimeValue(raw: $0) }
        }
    }
}

private final class RuntimeListSlice {
    let base: RuntimeListBox
    let fromIndex: Int
    var toIndex: Int
    var expectedModCount: Int

    init(base: RuntimeListBox, fromIndex: Int, toIndex: Int) {
        self.base = base
        self.fromIndex = fromIndex
        self.toIndex = toIndex
        expectedModCount = base.modCount
    }
}

/// Runtime box for `ArrayDeque<T>`.
///
/// Elements live in a ring buffer so that both ends mutate in place: `head` is
/// the buffer slot of the logical first element and `count` the number of live
/// elements. Growth doubles the buffer and re-linearizes it.
final class RuntimeArrayDequeBox {
    private var buffer: [RuntimeValue]
    private var head: Int
    private(set) var count: Int
    private(set) var modCount: Int = 0

    private static let minimumCapacity = 8

    var values: [RuntimeValue] {
        get {
            (0 ..< count).map { buffer[slot(forOffset: $0)] }
        }
        set {
            if newValue.count != count {
                modCount += 1
            }
            buffer = newValue
            head = 0
            count = newValue.count
            reserve(newValue.count)
        }
    }

    var elements: [Int] {
        get {
            values.map(\.legacyRawValue)
        }
        set {
            values = newValue.map { RuntimeValue(raw: $0) }
        }
    }

    init(capacity: Int) {
        buffer = Array(
            repeating: RuntimeValue(raw: 0),
            count: max(Self.minimumCapacity, capacity)
        )
        head = 0
        count = 0
    }

    init(values: [RuntimeValue]) {
        let capacity = max(Self.minimumCapacity, values.count)
        buffer = values
            + Array(repeating: RuntimeValue(raw: 0), count: capacity - values.count)
        head = 0
        count = values.count
    }

    func element(at index: Int) -> RuntimeValue? {
        guard index >= 0, index < count else { return nil }
        return buffer[slot(forOffset: index)]
    }

    func setValue(_ value: RuntimeValue, at index: Int) {
        let slot = slot(forOffset: index)
        buffer[slot] = runtimeValuePreservingAnyFallbackTag(value, existing: buffer[slot])
    }

    func pushFirst(_ value: RuntimeValue) {
        growIfNeeded()
        head = slot(forOffset: buffer.count - 1)
        buffer[head] = value
        count += 1
        modCount += 1
    }

    func pushLast(_ value: RuntimeValue) {
        growIfNeeded()
        buffer[slot(forOffset: count)] = value
        count += 1
        modCount += 1
    }

    func popFirst() -> RuntimeValue? {
        guard count > 0 else { return nil }
        let value = buffer[head]
        buffer[head] = RuntimeValue(raw: 0)
        head = slot(forOffset: 1)
        count -= 1
        modCount += 1
        return value
    }

    func popLast() -> RuntimeValue? {
        guard count > 0 else { return nil }
        let tail = slot(forOffset: count - 1)
        let value = buffer[tail]
        buffer[tail] = RuntimeValue(raw: 0)
        count -= 1
        modCount += 1
        return value
    }

    private func slot(forOffset offset: Int) -> Int {
        let capacity = buffer.count
        let index = head + offset
        return index < capacity ? index : index % capacity
    }

    private func growIfNeeded() {
        guard count == buffer.count else { return }
        reserve(max(Self.minimumCapacity, buffer.count * 2))
    }

    /// Re-linearizes the buffer so that `head == 0`, growing it to at least
    /// `capacity` slots.
    private func reserve(_ capacity: Int) {
        let target = max(Self.minimumCapacity, capacity)
        guard target != buffer.count || head != 0 else { return }
        var linearized = (0 ..< count).map { buffer[slot(forOffset: $0)] }
        if linearized.count < target {
            linearized += Array(repeating: RuntimeValue(raw: 0), count: target - linearized.count)
        }
        buffer = linearized
        head = 0
    }
}

/// Lazy wrapper for `withIndex()` result. Kotlin returns `IndexingIterable` with
/// default Object.toString() = "kotlin.collections.IndexingIterable@<hex>".
final class RuntimeIndexingIterableBox {
    let listRaw: Int

    init(listRaw: Int) {
        self.listRaw = listRaw
    }
}

/// Iterator for `withIndex()` result. Each call to `next()` yields an
/// `IndexedValue<E>` pair (index, element) represented as `RuntimePairBox`.
final class RuntimeIndexingIteratorBox {
    let values: [RuntimeValue]
    var index: Int

    init(values: [RuntimeValue]) {
        self.values = values
        index = 0
    }
}

/// Iterator box for `List` iteration via `for (x in list)`.
final class RuntimeListIteratorBox {
    var values: [RuntimeValue]
    var elements: [Int] {
        get {
            values.map(\.legacyRawValue)
        }
        set {
            values = newValue.map(runtimeValueFromCollectionABI)
        }
    }
    var index: Int
    /// Index last returned by `next()`/`previous()`, or -1 before any
    /// traversal call or once consumed by `remove()`/`add()` — mirrors
    /// Java/Kotlin's `AbstractList.Itr.lastRet` invariant.
    var lastReturnedIndex: Int
    let removeAction: ((Int) -> Void)?
    let setAction: ((Int, RuntimeValue) -> Void)?
    let addAction: ((Int, RuntimeValue) -> Void)?
    let isBackingReadOnly: (() -> Bool)?
    /// Reads the live backing collection's structural-modification counter.
    /// `nil` for iterators with no live backing (plain `Array`, or the
    /// BUG-231 empty fallback) — comodification can never be detected there.
    let currentModCount: (() -> Int)?
    let currentValue: ((Int) -> RuntimeValue)?
    /// The backing collection's `modCount` as of the last point this
    /// iterator observed it in sync (construction, or its own successful
    /// `remove()`/`add()`, which re-syncs after performing the mutation).
    var expectedModCount: Int

    init(
        elements: [Int],
        removeAction: ((Int) -> Void)? = nil,
        setAction: ((Int, RuntimeValue) -> Void)? = nil,
        addAction: ((Int, RuntimeValue) -> Void)? = nil,
        isBackingReadOnly: (() -> Bool)? = nil,
        currentModCount: (() -> Int)? = nil,
        currentValue: ((Int) -> RuntimeValue)? = nil
    ) {
        values = elements.map(runtimeValueFromCollectionABI)
        index = 0
        lastReturnedIndex = -1
        self.removeAction = removeAction
        self.setAction = setAction
        self.addAction = addAction
        self.isBackingReadOnly = isBackingReadOnly
        self.currentModCount = currentModCount
        self.currentValue = currentValue
        self.expectedModCount = currentModCount?() ?? 0
    }

    init(
        values: [RuntimeValue],
        removeAction: ((Int) -> Void)? = nil,
        setAction: ((Int, RuntimeValue) -> Void)? = nil,
        addAction: ((Int, RuntimeValue) -> Void)? = nil,
        isBackingReadOnly: (() -> Bool)? = nil,
        currentModCount: (() -> Int)? = nil,
        currentValue: ((Int) -> RuntimeValue)? = nil
    ) {
        self.values = values
        index = 0
        lastReturnedIndex = -1
        self.removeAction = removeAction
        self.setAction = setAction
        self.addAction = addAction
        self.isBackingReadOnly = isBackingReadOnly
        self.currentModCount = currentModCount
        self.currentValue = currentValue
        self.expectedModCount = currentModCount?() ?? 0
    }

    /// `true` when the backing collection has not structurally changed since
    /// this iterator last observed it. Iterators with no live backing always
    /// report in sync.
    func isInSyncWithBackingCollection() -> Bool {
        guard let currentModCount else { return true }
        return currentModCount() == expectedModCount
    }

    func removeLastReturned() -> Bool {
        guard lastReturnedIndex >= 0, lastReturnedIndex < values.count else {
            return false
        }
        values.remove(at: lastReturnedIndex)
        index = lastReturnedIndex
        removeAction?(lastReturnedIndex)
        lastReturnedIndex = -1
        // The removal above just went through `removeAction`, which mutates
        // the live backing collection (bumping its modCount) — resync so
        // this iterator's own next `next()` call does not see its own
        // change as a concurrent modification.
        if let currentModCount {
            expectedModCount = currentModCount()
        }
        return true
    }

    /// `MutableListIterator.set`: replaces the element most recently returned
    /// by `next()`/`previous()`, at the same position `removeLastReturned()`
    /// targets.
    func setLastReturned(_ value: RuntimeValue) -> Bool {
        guard lastReturnedIndex >= 0, lastReturnedIndex < values.count else {
            return false
        }
        values[lastReturnedIndex] = value
        setAction?(lastReturnedIndex, value)
        return true
    }

    /// `MutableListIterator.add`: inserts before the element `next()` would
    /// return, then advances the cursor past the inserted element so a
    /// following `next()` does not return it again. Invalidates
    /// `lastReturnedIndex`: `add()` cannot be followed directly by
    /// `set()`/`remove()`.
    func addBeforeNext(_ value: RuntimeValue) {
        values.insert(value, at: index)
        addAction?(index, value)
        index += 1
        lastReturnedIndex = -1
        // Same resync rationale as `removeLastReturned()` above.
        if let currentModCount {
            expectedModCount = currentModCount()
        }
    }
}

// MARK: - RuntimeChildReferenceProviding conformances (ABI-004)
//
// These conformances enable the recursive BFS freeze in kk_freeze_object to
// traverse all reachable object references when freezing an object graph.
// Only types that store `Int` child handles need to conform.

extension RuntimeListBox: RuntimeChildReferenceProviding {
    private func childReference(at index: Int) -> Int? {
        // Traverse backing storage without allocating temporary primitive boxes.
        switch storage {
        case .arrayViewOf(let base, let kind):
            return kind == nil ? base.values[index].childReferenceRawValue : nil
        case .reversedViewOf(let base):
            return base.childReference(at: base.count - 1 - index)
        case .subList(let slice):
            return slice.base.childReference(at: slice.fromIndex + index)
        default:
            return value(at: index).childReferenceRawValue
        }
    }

    var childRefs: [Int] { indices.compactMap { childReference(at: $0) } }
}

extension RuntimeArrayDequeBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] { values.compactMap(\.childReferenceRawValue) }
}
