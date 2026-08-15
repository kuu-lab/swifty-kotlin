
let indexedValueRuntimeTypeID: Int64 = {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in "kotlin.collections.IndexedValue".utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x100_0000_01B3
    }
    let payloadMask: Int64 = (1 << 55) - 1
    let payload = Int64(bitPattern: hash) & payloadMask
    return payload == 0 ? 1 : payload
}()

func runtimeIndexedValueNew(index: Int, value: Int) -> Int {
    runtimeIndexedValueNew(index: index, value: RuntimeValue(raw: value))
}

func runtimeIndexedValueNew(index: Int, value: RuntimeValue) -> Int {
    let raw = runtimePairNew(
        firstValue: RuntimeValue(raw: index),
        secondValue: value
    )
    runtimeRegisterObjectType(rawValue: raw, classID: indexedValueRuntimeTypeID)
    return raw
}

@_cdecl("kk_indexed_value_new")
public func kk_indexed_value_new(_ index: Int, _ value: Int) -> Int {
    runtimeIndexedValueNew(index: index, value: value)
}

/// KSP-626: `IndexedValue` is a source-backed Kotlin data class, so its
/// instances are ordinary heap objects (index@2, value@3). The Any-erased
/// print/toString paths cannot invoke the generated `toString`, so render such
/// an instance here — mirroring the legacy Pair-box special case. Returns nil
/// for any other object.
func runtimeRenderIndexedValueObject(_ raw: Int, render: (RuntimeValue) -> String) -> String? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let box = tryCast(ptr, to: RuntimeObjectBox.self),
          box.classID == indexedValueRuntimeTypeID,
          box.values.count >= 4
    else {
        return nil
    }
    return "IndexedValue(index=\(render(box.values[2])), value=\(render(box.values[3])))"
}

func handleCollectionLambdaThrow(_ thrown: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let outThrown = outThrown {
        outThrown.pointee = thrown
        return runtimeExceptionCaughtSentinel
    } else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Uncaught exception in collection HOF lambda. outThrown was nil.")
    }
}

/// Panics when a collection HOF receives an invalid container handle.
/// Replaces silent fallbacks (return empty list/map/0/false) that mask runtime corruption.
func invalidContainerPanic(_ caller: StaticString, _ kind: StaticString) -> Never {
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid \(kind) handle")
}

/// Builds a key-index dictionary from existing map keys for O(1) lookups.
func buildKeyIndex(from dest: RuntimeMapBox) -> [Int: Int] {
    var keyIndex: [Int: Int] = [:]
    for (i, k) in dest.keys.enumerated() {
        keyIndex[k] = i
    }
    return keyIndex
}

/// Inserts or updates a key-value pair in a destination map, maintaining the key index.
@discardableResult
func mapInsertOrUpdate(
    dest: RuntimeMapBox,
    keyIndex: inout [Int: Int],
    key: Int,
    value: Int
) -> Int {
    if let index = keyIndex[key] {
        dest.values[index] = value
        return index
    } else {
        let newIndex = dest.keys.count
        dest.keys.append(key)
        dest.values.append(value)
        keyIndex[key] = newIndex
        return newIndex
    }
}

@inline(__always)
func runtimeSortedWithComparatorInvoke(
    fnPtr: Int,
    closureRaw: Int
) -> (Int, Int, UnsafeMutablePointer<Int>?) -> Int {
    if closureRaw == 0,
       let rawPointer = UnsafeMutableRawPointer(bitPattern: fnPtr),
       runtimeStorage.withGCLock({ state in state.objectPointers.contains(UInt(bitPattern: rawPointer)) })
    {
        let compareFnPtr = kk_itable_lookup(fnPtr, 0, 0)
        if compareFnPtr != 0 {
            let compareFn = unsafeBitCast(compareFnPtr, to: RuntimeCollectionLambda2.self)
            return { lhs, rhs, outThrown in
                compareFn(fnPtr, maybeUnbox(lhs), maybeUnbox(rhs), outThrown)
            }
        }

        if runtimeIsHeapObject(fnPtr) {
            let vtableCompareFnPtr = kk_vtable_lookup(fnPtr, 0)
            guard vtableCompareFnPtr != 0 else {
                fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: runtimeSortedWithComparatorInvoke received a heap object comparator with null vtable compare method at slot 0")
            }
            let vtableCompareFn = unsafeBitCast(vtableCompareFnPtr, to: RuntimeCollectionLambda2.self)
            return { lhs, rhs, outThrown in
                vtableCompareFn(fnPtr, maybeUnbox(lhs), maybeUnbox(rhs), outThrown)
            }
        }

        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: runtimeSortedWithComparatorInvoke received a registered comparator object without an itable or vtable compare method")
    }

    let compareFn = unsafeBitCast(fnPtr, to: RuntimeCollectionLambda2.self)
    return { lhs, rhs, outThrown in
        compareFn(maybeUnbox(closureRaw), maybeUnbox(lhs), maybeUnbox(rhs), outThrown)
    }
}

// MARK: - Closeable.use {} (STDLIB-250)

private final class RuntimeAutoCloseableBox {
    let fnPtr: Int
    let closureRaw: Int

    init(fnPtr: Int, closureRaw: Int) {
        self.fnPtr = fnPtr
        self.closureRaw = closureRaw
    }
}

private let runtimeAutoCloseableCloseThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { receiverRaw, outThrown in
    guard let pointer = UnsafeMutableRawPointer(bitPattern: receiverRaw),
          let box = tryCast(pointer, to: RuntimeAutoCloseableBox.self)
    else {
        let thrown = runtimeAllocateThrowable(message: "AutoCloseable receiver is invalid.")
        return handleCollectionLambdaThrow(thrown, outThrown)
    }

    var thrown = 0
    _ = runtimeInvokeClosureThunk(fnPtr: box.fnPtr, closureRaw: box.closureRaw, outThrown: &thrown)
    if thrown != 0 {
        return handleCollectionLambdaThrow(thrown, outThrown)
    }
    return 0
}

/// AutoCloseable is a typealias for Closeable (see
/// HeaderHelpers+SyntheticCloseableStubs.swift), so its stable nominal type ID
/// for itableDynamic dispatch is Closeable's, keyed by "kotlin.io.Closeable".
private let runtimeCloseableInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.io.Closeable")

/// `AutoCloseable { closeAction }` factory. KSP-611: the public factory is Kotlin
/// source (Stdlib/kotlin/io/Closeable.kt) delegating to this demoted bridge.
@_cdecl("__kk_auto_closeable_create")
public func kk_auto_closeable_create(_ fnPtr: Int, _ closureRaw: Int) -> Int {
    let resourceRaw = registerRuntimeObject(RuntimeAutoCloseableBox(fnPtr: fnPtr, closureRaw: closureRaw))
    _ = kk_object_register_itable_method(
        resourceRaw,
        0,
        0,
        unsafeBitCast(runtimeAutoCloseableCloseThunk, to: Int.self)
    )
    // A user-written generic function typed `(c: AutoCloseable) -> Unit` that
    // calls `c.close()` directly (not through the inline-expanded `use {}`)
    // dispatches via kk_itable_lookup_dynamic, which needs this registration
    // — see the identical Comparator gap fixed in RuntimeComparator.swift.
    _ = kk_object_register_itable_iface(resourceRaw, Int(runtimeCloseableInterfaceTypeID), 0)
    return resourceRaw
}

@_cdecl("__kk_iterable_firstNotNullOf")
public func kk_iterable_firstNotNullOf(_ iterableRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionOrArrayElements(from: iterableRaw) else {
        invalidContainerPanic(#function, "iterable")
    }
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if let normalized = runtimeMapNotNullResultValue(result) {
            return normalized
        }
    }
    let thrown = runtimeAllocateNoSuchElementException(message: "No element of the collection was transformed to a non-null value.")
    return handleCollectionLambdaThrow(thrown, outThrown)
}

@_cdecl("__kk_iterable_firstNotNullOfOrNull")
public func kk_iterable_firstNotNullOfOrNull(_ iterableRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionOrArrayElements(from: iterableRaw) else {
        invalidContainerPanic(#function, "iterable")
    }
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if let normalized = runtimeMapNotNullResultValue(result) {
            return normalized
        }
    }
    return runtimeNullSentinelInt
}




@_cdecl("__kk_iterable_requireNoNulls")
public func kk_iterable_requireNoNulls(_ iterableRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionElements(from: iterableRaw) else {
        invalidContainerPanic(#function, "iterable")
    }
    for elem in elements where runtimeNormalizeNullableCollectionValue(elem) == nil {
        let thrown = runtimeAllocateIllegalArgumentException(message: "null element found in collection.")
        return handleCollectionLambdaThrow(thrown, outThrown)
    }
    return iterableRaw
}

@_cdecl("kk_list_forEach")
public func kk_list_forEach(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    for elem in list.elements {
        var thrown = 0
        _ = runtimeInvokeCollectionLambda1PreservingBox(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return 0
}

@_cdecl("__kk_iterable_any")
public func kk_iterable_any(_ iterableRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionElements(from: iterableRaw) ?? runtimeArrayBox(from: iterableRaw)?.elements else {
        invalidContainerPanic(#function, "iterable")
    }
    if fnPtr == 0 {
        return elements.isEmpty ? 0 : 1
    }
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return 1 }
    }
    return 0
}

@_cdecl("__kk_iterable_all")
public func kk_iterable_all(_ iterableRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionElements(from: iterableRaw) ?? runtimeArrayBox(from: iterableRaw)?.elements else {
        invalidContainerPanic(#function, "iterable")
    }
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) == 0 { return 0 }
    }
    return 1
}










// MARK: - STDLIB-535/536/537: associateByTo / associateWithTo / groupByTo

/// Builds a key-index dictionary from existing map keys for O(1) lookups.
/// Shared helper to avoid duplicating key-index precomputation across *To functions.

/// Inserts or updates a key-value pair in a destination map, maintaining the key index.
/// Returns the updated key index.
@discardableResult




// MARK: - ListWindowChunk private bridges (KSP-307)

@_cdecl("__kk_list_zip")
public func kk_list_bridge_zip(_ listRaw: Int, _ otherRaw: Int) -> Int {
    guard let lhs = runtimeCollectionOrArrayElements(from: listRaw) else { invalidContainerPanic(#function, "collection") }
    guard let rhs = runtimeCollectionOrArrayElements(from: otherRaw) else { invalidContainerPanic(#function, "collection") }
    let count = min(lhs.count, rhs.count)
    var pairs: [Int] = []
    pairs.reserveCapacity(count)
    for index in 0 ..< count {
        pairs.append(kk_pair_new(lhs[index], rhs[index]))
    }
    return registerRuntimeObject(RuntimeListBox(elements: pairs))
}

@_cdecl("__kk_list_zip_transform")
public func kk_list_bridge_zip_transform(
    _ listRaw: Int,
    _ otherRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let lhs = runtimeCollectionOrArrayElements(from: listRaw) else { invalidContainerPanic(#function, "collection") }
    guard let rhs = runtimeCollectionOrArrayElements(from: otherRaw) else { invalidContainerPanic(#function, "collection") }
    let count = min(lhs.count, rhs.count)
    var results: [Int] = []
    results.reserveCapacity(count)
    for index in 0 ..< count {
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: lhs[index],
            rhs: rhs[index],
            outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        results.append(maybeUnbox(transformed))
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

@_cdecl("__kk_list_chunked")
public func kk_list_bridge_chunked(_ listRaw: Int, _ size: Int) -> Int {
    guard let elements = runtimeCollectionOrArrayElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    let clampedSize = max(1, size)
    var chunks: [Int] = []
    var i = 0
    while i < elements.count {
        let end = min(i + clampedSize, elements.count)
        let chunk = Array(elements[i ..< end])
        chunks.append(registerRuntimeObject(RuntimeListBox(elements: chunk)))
        i = end
    }
    return registerRuntimeObject(RuntimeListBox(elements: chunks))
}

@_cdecl("__kk_list_chunked_transform")
public func kk_list_bridge_chunked_transform(_ listRaw: Int, _ size: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionOrArrayElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    let clampedSize = max(1, size)
    let estimatedChunks = elements.isEmpty ? 0 : (elements.count + clampedSize - 1) / clampedSize
    var result: [Int] = []
    result.reserveCapacity(estimatedChunks)
    var i = 0
    while i < elements.count {
        let end = min(i + clampedSize, elements.count)
        let chunk = Array(elements[i ..< end])
        let chunkList = registerRuntimeObject(RuntimeListBox(elements: chunk))
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1MaybeWrapped(fnPtr: fnPtr, closureRaw: closureRaw, value: chunkList, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        result.append(maybeUnbox(transformed))
        i = end
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("__kk_list_windowed")
public func kk_list_bridge_windowed(_ listRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    guard let elements = runtimeCollectionOrArrayElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    let clampedSize = max(1, size)
    let clampedStep = max(1, step)
    let partial = partialWindows != 0
    var windows: [Int] = []
    var i = 0
    while i < elements.count {
        let end = min(i + clampedSize, elements.count)
        if !partial && end - i < clampedSize { break }
        let window = Array(elements[i ..< end])
        windows.append(registerRuntimeObject(RuntimeListBox(elements: window)))
        i += clampedStep
    }
    return registerRuntimeObject(RuntimeListBox(elements: windows))
}

@_cdecl("__kk_list_windowed_transform")
public func kk_list_bridge_windowed_transform(
    _ listRaw: Int,
    _ size: Int,
    _ step: Int,
    _ partialWindows: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let elements = runtimeCollectionOrArrayElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    let clampedSize = max(1, size)
    let clampedStep = max(1, step)
    let partial = partialWindows != 0
    var result: [Int] = []
    var i = 0
    while i < elements.count {
        let end = min(i + clampedSize, elements.count)
        if !partial && end - i < clampedSize { break }
        let window = Array(elements[i ..< end])
        let windowList = registerRuntimeObject(RuntimeListBox(elements: window))
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1MaybeWrapped(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: windowList,
            outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        result.append(maybeUnbox(transformed))
        i += clampedStep
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("__kk_list_zipWithNext")
public func kk_list_bridge_zipWithNext(_ listRaw: Int) -> Int {
    guard let elems = runtimeCollectionOrArrayElements(from: listRaw) else { invalidContainerPanic(#function, "collection") }
    guard elems.count >= 2 else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    var pairs: [Int] = []
    pairs.reserveCapacity(elems.count - 1)
    for i in 0 ..< elems.count - 1 {
        pairs.append(kk_pair_new(elems[i], elems[i + 1]))
    }
    return registerRuntimeObject(RuntimeListBox(elements: pairs))
}

@_cdecl("__kk_list_zipWithNextTransform")
public func kk_list_bridge_zipWithNextTransform(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elems = runtimeCollectionOrArrayElements(from: listRaw) else { invalidContainerPanic(#function, "collection") }
    guard elems.count >= 2 else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    var results: [Int] = []
    results.reserveCapacity(elems.count - 1)
    for i in 0 ..< elems.count - 1 {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: elems[i], rhs: elems[i + 1], outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        results.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

// MARK: - IndexingIterable iterator (for destructuring `for ((i, v) in list.withIndex())`)

@_cdecl("kk_indexing_iterable_iterator")
public func kk_indexing_iterable_iterator(_ iterableRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: iterableRaw),
          let box = tryCast(ptr, to: RuntimeIndexingIterableBox.self),
          let list = runtimeListBox(from: box.listRaw)
    else {
        return 0
    }
    return registerRuntimeObject(RuntimeIndexingIteratorBox(values: list.values))
}

@_cdecl("kk_indexing_iterable_hasNext")
public func kk_indexing_iterable_hasNext(_ iterRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: iterRaw),
          let iter = tryCast(ptr, to: RuntimeIndexingIteratorBox.self) else {
        return 0
    }
    return iter.index < iter.values.count ? 1 : 0
}

@_cdecl("kk_indexing_iterable_next")
public func kk_indexing_iterable_next(_ iterRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: iterRaw),
          let iter = tryCast(ptr, to: RuntimeIndexingIteratorBox.self),
          iter.index < iter.values.count
    else {
        return 0
    }
    let idx = iter.index
    let elem = iter.values[idx]
    iter.index += 1
    return runtimeIndexedValueNew(index: idx, value: elem)
}


@_cdecl("kk_list_sumOf")
public func kk_list_sumOf(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var total = 0
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        total += maybeUnbox(result)
    }
    return total
}

@_cdecl("kk_list_sumBy")
public func kk_list_sumBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionElements(from: listRaw) ?? runtimeArrayBox(from: listRaw)?.elements else {
        invalidContainerPanic(#function, "list")
    }
    var total = 0
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        total += maybeUnbox(result)
    }
    return total
}

@_cdecl("kk_list_sumByDouble")
public func kk_list_sumByDouble(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionElements(from: listRaw) ?? runtimeArrayBox(from: listRaw)?.elements else {
        invalidContainerPanic(#function, "list")
    }
    var total = 0.0
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        total += kk_bits_to_double(result)
    }
    return kk_double_to_bits(total)
}










@_cdecl("kk_list_shuffled_random")
public func kk_list_shuffled_random(_ listRaw: Int, _ randomRaw: Int) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var elements = listBox.elements
    // Fisher-Yates shuffle delegating to runtimeRandomNextIntBelow, which
    // (KSP-466) currently ignores the Random instance and uses Swift's
    // SystemRandomNumberGenerator, so seeded Random instances (e.g.
    // Random(42)) do NOT yet produce deterministic results here. The
    // randomRaw parameter is threaded through so that adding seeded RNG
    // support requires changes only in RuntimeRandom.swift.
    guard elements.count > 1 else {
        return registerRuntimeObject(RuntimeListBox(elements: elements))
    }
    for i in stride(from: elements.count - 1, through: 1, by: -1) {
        let j = runtimeRandomNextIntBelow(randomRaw, i + 1)
        elements.swapAt(i, j)
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("kk_list_random")
public func kk_list_random(_ listRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let elements = runtimeCollectionElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    guard !elements.isEmpty else {
        return handleCollectionLambdaThrow(runtimeAllocateNoSuchElementException(message: "Collection is empty."), outThrown)
    }
    return elements.randomElement()!
}

@_cdecl("kk_list_randomOrNull")
public func kk_list_randomOrNull(_ listRaw: Int) -> Int {
    guard let elements = runtimeCollectionElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    guard let element = elements.randomElement() else {
        return runtimeNullSentinelInt
    }
    return element
}


// MARK: - Collection sorting compatibility

// `sortedBy` is source-backed for List receivers, but Iterable/Collection/Set
// receivers (for example Map.entries) still use this ABI-compatible bridge.
@_cdecl("kk_list_sortedBy")
public func kk_list_sortedBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionElements(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard let sorted = runtimeSortByElements(
        elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        descending: false,
        primitiveKind: nil,
        outThrown: outThrown
    ) else {
        return handleCollectionLambdaThrow(outThrown?.pointee ?? 0, outThrown)
    }
    return registerRuntimeObject(RuntimeListBox(elements: sorted.map(\.element)))
}

private func runtimeSortByElements(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    descending: Bool,
    primitiveKind: RuntimePrimitiveCompareKind?,
    outThrown: UnsafeMutablePointer<Int>?
) -> [(offset: Int, element: Int)]? {
    var indexed: [(offset: Int, element: Int, key: Int)] = []
    indexed.reserveCapacity(elements.count)
    for elem in elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            if let outThrown {
                outThrown.pointee = thrown
            } else {
                fatalError("KSwiftK panic [\\(runtimePanicDiagnosticCode)]: Uncaught exception in collection HOF lambda. outThrown was nil.")
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
