
@_cdecl("kk_list_take")
public func kk_list_take(_ listRaw: Int, _ count: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    outThrown?.pointee = 0
    if count < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(count) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let elements = _listBox.elements
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.prefix(clamped))))
}

@_cdecl("kk_list_drop")
public func kk_list_drop(_ listRaw: Int, _ count: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    outThrown?.pointee = 0
    if count < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(count) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let elements = _listBox.elements
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.dropFirst(clamped))))
}

@_cdecl("kk_list_takeLast")
public func kk_list_takeLast(_ listRaw: Int, _ count: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    outThrown?.pointee = 0
    if count < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(count) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let elements = _listBox.elements
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.suffix(clamped))))
}

@_cdecl("kk_list_dropLast")
public func kk_list_dropLast(_ listRaw: Int, _ count: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.dropLast(clamped))))
}

@_cdecl("kk_list_sum")
public func kk_list_sum(_ listRaw: Int) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var total = 0
    for element in listBox.elements {
        // Lists produced by compiled Kotlin code store boxed primitives.
        total &+= maybeUnbox(element)
    }
    return total
}

@_cdecl("kk_list_average")
public func kk_list_average(_ listRaw: Int) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = listBox.elements
    guard !elements.isEmpty else { return kk_double_to_bits(Double.nan) }
    var sum: Double = 0.0
    for raw in elements {
        if let ptr = UnsafeMutableRawPointer(bitPattern: raw) {
            let isObj = runtimeStorage.withGCLock { state in
                state.objectPointers.contains(UInt(bitPattern: ptr))
            }
            if isObj {
                if let doubleBox = tryCast(ptr, to: RuntimeDoubleBox.self) {
                    sum += doubleBox.value
                    continue
                } else if let floatBox = tryCast(ptr, to: RuntimeFloatBox.self) {
                    sum += Double(floatBox.value)
                    continue
                } else if let longBox = tryCast(ptr, to: RuntimeLongBox.self) {
                    sum += Double(longBox.value)
                    continue
                } else if let ulongBox = tryCast(ptr, to: RuntimeULongBox.self) {
                    sum += Double(UInt(bitPattern: ulongBox.value))
                    continue
                } else if let intBox = tryCast(ptr, to: RuntimeIntBox.self) {
                    sum += Double(intBox.value)
                    continue
                }
            }
        }
        // Unboxed raw integer (plain Int list element)
        sum += Double(raw)
    }
    return kk_double_to_bits(sum / Double(elements.count))
}

@_cdecl("kk_list_reversed")
public func kk_list_reversed(_ listRaw: Int) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = listBox.elements
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.reversed())))
}

@_cdecl("kk_list_as_reversed")
public func kk_list_as_reversed(_ listRaw: Int) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    return registerRuntimeObject(RuntimeListBox(reversedViewOf: listBox))
}


@inline(__always)
func runtimePrimitiveCompareKindFromRaw(_ raw: Int32) -> RuntimePrimitiveCompareKind {
    switch raw {
    case 1: return .long
    case 2: return .uint
    case 3: return .ulong
    case 4: return .boolean
    case 5: return .char
    case 6: return .float
    case 7: return .double
    default: return .int
    }
}

@inline(__always)
func runtimeSortElements(
    _ elements: [Int],
    descending: Bool,
    primitiveKind: RuntimePrimitiveCompareKind
) -> [Int] {
    return elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeComparePrimitiveValues(lhs.element, rhs.element, kind: primitiveKind)
        if comparison != 0 {
            return descending ? comparison > 0 : comparison < 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
}

@inline(__always)
func runtimeSortByElements(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    descending: Bool,
    primitiveKind: RuntimePrimitiveCompareKind?,
    outThrown: UnsafeMutablePointer<Int>?
) -> [(offset: Int, element: Int)]? {
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var indexed: [(offset: Int, element: Int, key: Int)] = []
    indexed.reserveCapacity(elements.count)
    for elem in elements {
        var thrown = 0
        let key = lambda(closureRaw, elem, &thrown)
        if thrown != 0 {
            if let outThrown {
                outThrown.pointee = thrown
            } else {
                fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Uncaught exception in collection HOF lambda. outThrown was nil.")
            }
            return nil
        }
        indexed.append((offset: indexed.count, element: elem, key: key))
    }
    let sorted = indexed.sorted { lhs, rhs in
        let comparison: Int
        if let primitiveKind {
            comparison = runtimeComparePrimitiveValues(lhs.key, rhs.key, kind: primitiveKind)
        } else {
            comparison = runtimeCompareValues(lhs.key, rhs.key)
        }
        if comparison != 0 {
            return descending ? comparison > 0 : comparison < 0
        }
        return lhs.offset < rhs.offset
    }
    return sorted.map { (offset: $0.offset, element: $0.element) }
}



@_cdecl("kk_set_sorted")
public func kk_set_sorted(_ setRaw: Int) -> Int {
    guard let _setBox = runtimeSetBox(from: setRaw) else { invalidContainerPanic(#function, "set") }
    let elements = _setBox.elements
    let sorted = elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 {
            return comparison < 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    return registerRuntimeObject(RuntimeListBox(elements: sorted))
}

@_cdecl("kk_list_distinct")
public func kk_list_distinct(_ listRaw: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    return registerRuntimeObject(RuntimeListBox(elements: runtimeDeduplicatePreservingOrder(elements)))
}

/// Returns a list containing only elements with distinct keys returned by the selector.
///
/// Key deduplication uses `RuntimeElementKey` which delegates to
/// `kk_any_hashCode` / `runtimeValuesEqual` for structural equality,
/// so data-class and other reference-typed keys compare by value.
@_cdecl("kk_list_distinctBy")
public func kk_list_distinctBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var seenKeys = Set<RuntimeElementKey>()
    seenKeys.reserveCapacity(list.elements.count)
    var result: [Int] = []
    result.reserveCapacity(list.elements.count)
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if seenKeys.insert(RuntimeElementKey(value: key)).inserted {
            result.append(elem)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_list_shuffled")
public func kk_list_shuffled(_ listRaw: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let shuffled = elements.shuffled()
    return registerRuntimeObject(RuntimeListBox(elements: shuffled))
}

/// Collection<T : Comparable>.max(): T (throws NoSuchElementException if empty)
