
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
