import Foundation

final class RuntimeListBox {
    private final class DirectStorage {
        var values: [RuntimeValue]
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

    private func arrayViewValue(_ value: RuntimeValue, kind: RuntimePrimitiveArrayElementKind?) -> RuntimeValue {
        guard let kind else { return value }
        let raw = value.legacyRawValue
        switch kind {
        case .boolean: return RuntimeValue(raw: kk_box_bool(raw))
        case .byte: return RuntimeValue(raw: kk_box_byte(raw))
        case .char: return RuntimeValue(raw: kk_box_char(raw))
        case .double: return RuntimeValue(raw: kk_box_double_nonnull(raw))
        case .float: return RuntimeValue(raw: kk_box_float(raw))
        case .int: return RuntimeValue(raw: kk_box_int(raw))
        case .long: return RuntimeValue(raw: kk_box_long_nonnull(raw))
        case .short: return RuntimeValue(raw: kk_box_short(raw))
        // The unsigned value classes are stored sign-extended inside their
        // signed backing arrays; the boxed element carries the zero-extended
        // payload so generic toString/hashCode/`is` see the logical value.
        case .uByte: return RuntimeValue(raw: kk_box_ubyte(Int(UInt8(truncatingIfNeeded: raw))))
        case .uShort: return RuntimeValue(raw: kk_box_ushort(Int(UInt16(truncatingIfNeeded: raw))))
        case .uInt: return RuntimeValue(raw: kk_box_uint(Int(UInt32(truncatingIfNeeded: raw))))
        case .uLong: return RuntimeValue(raw: kk_box_ulong_nonnull(raw))
        }
    }

    private func arrayStorageValue(_ value: RuntimeValue, kind: RuntimePrimitiveArrayElementKind?) -> RuntimeValue {
        guard let kind else { return value }
        let raw = runtimeCollectionABIValue(value)
        switch kind {
        case .boolean: return RuntimeValue(raw: kk_unbox_bool_static(raw))
        case .byte: return RuntimeValue(raw: Int(Int8(truncatingIfNeeded: kk_unbox_int(raw))))
        case .char: return RuntimeValue(raw: kk_unbox_char_static(raw))
        case .double: return RuntimeValue(raw: kk_unbox_double_nonnull_static(raw))
        case .float: return RuntimeValue(raw: kk_unbox_float_static(raw))
        case .int: return RuntimeValue(raw: kk_unbox_int(raw))
        case .long: return RuntimeValue(raw: kk_unbox_long(raw))
        case .short: return RuntimeValue(raw: Int(Int16(truncatingIfNeeded: kk_unbox_int(raw))))
        // Writes normalize to the sign-extended storage of the signed
        // backing array each unsigned value class wraps (UByteArray sits on
        // ByteArray, UShortArray on ShortArray, UIntArray on IntArray).
        case .uByte: return RuntimeValue(raw: Int(Int8(truncatingIfNeeded: kk_unbox_int(raw))))
        case .uShort: return RuntimeValue(raw: Int(Int16(truncatingIfNeeded: kk_unbox_int(raw))))
        case .uInt: return RuntimeValue(raw: Int(Int32(truncatingIfNeeded: kk_unbox_int(raw))))
        case .uLong: return RuntimeValue(raw: kk_unbox_ulong(raw))
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
                guard newValue.isEmpty,
                      let map = runtimeMapBox(from: mapRaw),
                      !map.isEffectivelyReadOnly
                else { return }
                map.removeAll()
            }
        }
    }

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
                break
            }
        }
    }

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
            break
        }
    }

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

    var isMapValuesView: Bool {
        if case .mapValuesViewOf = storage { return true }
        return false
    }

    var mapValuesViewBackingRaw: Int? {
        guard case .mapValuesViewOf(let mapRaw) = storage else { return nil }
        return mapRaw
    }

    var isSubListStorageView: Bool {
        if case .subList = storage { return true }
        return false
    }

    var subListBaseBox: RuntimeListBox? {
        guard case .subList(let slice) = storage else { return nil }
        return slice.base
    }

    var isArrayStorageView: Bool {
        if case .arrayViewOf = storage { return true }
        return false
    }

    var isPrimitiveArrayView: Bool {
        guard case .arrayViewOf(_, let elementKind) = storage else { return false }
        return elementKind != nil
    }

    var isDequeStorageView: Bool {
        if case .dequeViewOf = storage { return true }
        return false
    }

    var isReversedStorageView: Bool {
        if case .reversedViewOf = storage { return true }
        return false
    }

    var usesReferenceEquality: Bool {
        guard case let .mapValuesViewOf(raw) = storage else { return false }
        return runtimeMapBox(from: raw)?.usesReferenceEquality == true
    }

    func removeValues(where predicate: (RuntimeValue) -> Bool) {
        if isMapValuesView {
            for index in (0..<count).reversed() where predicate(value(at: index)) {
                _ = removeMapBackedValue(at: index)
            }
        } else {
            withMutableValues { $0.removeAll(where: predicate) }
        }
    }

    func elementsEqual(_ lhs: Int, _ rhs: Int) -> Bool {
        if case let .mapValuesViewOf(mapRaw) = storage,
           let map = runtimeMapBox(from: mapRaw) {
            return map.valuesEqual(lhs, rhs)
        }
        return runtimeLookupValuesEqual(lhs, rhs)
    }

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

final class RuntimeIndexingIterableBox {
    let listRaw: Int

    init(listRaw: Int) {
        self.listRaw = listRaw
    }
}

/// Each call to `next()` yields an `IndexedValue<E>` pair (index, element)
/// represented as the source data class's `RuntimeObjectBox` (index@2, value@3).
final class RuntimeIndexingIteratorBox {
    let values: [RuntimeValue]
    var index: Int

    init(values: [RuntimeValue]) {
        self.values = values
        index = 0
    }
}

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
    var lastReturnedIndex: Int
    let removeAction: ((Int) -> Void)?
    let setAction: ((Int, RuntimeValue) -> Void)?
    let addAction: ((Int, RuntimeValue) -> Void)?
    let isBackingReadOnly: (() -> Bool)?
    let currentModCount: (() -> Int)?
    let currentValue: ((Int) -> RuntimeValue)?
    var expectedModCount: Int

    var reflectedClassID: Int64 = 0
    var reflectedClassName: String? = nil

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

    func setLastReturned(_ value: RuntimeValue) -> Bool {
        guard lastReturnedIndex >= 0, lastReturnedIndex < values.count else {
            return false
        }
        values[lastReturnedIndex] = value
        setAction?(lastReturnedIndex, value)
        return true
    }

    func addBeforeNext(_ value: RuntimeValue) {
        values.insert(value, at: index)
        addAction?(index, value)
        index += 1
        lastReturnedIndex = -1
        if let currentModCount {
            expectedModCount = currentModCount()
        }
    }
}

extension RuntimeListBox: RuntimeChildReferenceProviding {
    private func childReference(at index: Int) -> Int? {
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

    var childRefs: [Int] {
        var references: [Int] = []
        var current = self
        while true {
            switch current.storage {
            case let .mapValuesViewOf(mapRaw):
                if mapRaw != 0 { references.append(mapRaw) }
                return references
            case let .reversedViewOf(base):
                references.append(Int(bitPattern: Unmanaged.passUnretained(base).toOpaque()))
                current = base
            case let .subList(slice):
                references.append(Int(bitPattern: Unmanaged.passUnretained(slice.base).toOpaque()))
                current = slice.base
            default:
                references.append(contentsOf: current.indices.compactMap { current.childReference(at: $0) })
                return references
            }
        }
    }

    /// The collector holds gcLock and must not acquire an array view lock.
    func gcChildRefsLocked(state: GCState) -> [Int] {
        var references: [Int] = []
        var current = self
        while true {
            switch current.storage {
            case let .mapValuesViewOf(mapRaw):
                if mapRaw != 0 { references.append(mapRaw) }
                return references
            case let .reversedViewOf(base):
                references.append(Int(bitPattern: Unmanaged.passUnretained(base).toOpaque()))
                current = base
            case let .subList(slice):
                references.append(Int(bitPattern: Unmanaged.passUnretained(slice.base).toOpaque()))
                current = slice.base
            case let .arrayViewOf(base, kind):
                if kind == nil { references.append(contentsOf: base.gcStorageChildRefsLocked(state: state)) }
                return references
            case let .dequeViewOf(base):
                references.append(contentsOf: base.childRefs)
                return references
            case let .direct(direct):
                references.append(contentsOf: direct.values.compactMap(\.childReferenceRawValue))
                return references
            }
        }
    }

    func gcArrayStorageID() -> ObjectIdentifier? {
        var current = self
        while true {
            switch current.storage {
            case let .reversedViewOf(base):
                current = base
            case let .subList(slice):
                current = slice.base
            case let .arrayViewOf(base, kind):
                return kind == nil ? base.gcStorageID : nil
            case .direct, .dequeViewOf, .mapValuesViewOf:
                return nil
            }
        }
    }
}

extension RuntimeArrayDequeBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] { values.compactMap(\.childReferenceRawValue) }
}
