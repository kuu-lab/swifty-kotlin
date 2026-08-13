// swiftlint:disable file_length
#if canImport(Testing)
@testable import Runtime
import Foundation
import Testing

/// Test-only shims for KSP-426 List sort/max/min runtime entry points that
/// remain test-only after source migration. The generic `kk_list_sortedBy`
/// bridge is provided by production Runtime for Set/Iterable receivers.
/// These `@_cdecl` implementations are linked only by `RuntimeCollectionHOFTests`
/// to keep the historical ABI test surface working after the production
/// runtime functions were removed in favor of bundled Kotlin source.

@inline(__always)
private func runtimePrimitiveCompareKindFromRaw(_ raw: Int32) -> RuntimePrimitiveCompareKind {
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
private func runtimeSortElements(
    _ elements: [Int],
    descending: Bool,
    primitiveKind: RuntimePrimitiveCompareKind
) -> [Int] {
    elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeComparePrimitiveValues(lhs.element, rhs.element, kind: primitiveKind)
        if comparison != 0 {
            return descending ? comparison > 0 : comparison < 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
}

@inline(__always)
private func runtimeSortByElements(
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
            outThrown?.pointee = thrown
            return nil
        }
        indexed.append((offset: indexed.count, element: elem, key: key))
    }
    let sorted = indexed.sorted { lhs, rhs in
        let comparison = if let primitiveKind {
            runtimeComparePrimitiveValues(lhs.key, rhs.key, kind: primitiveKind)
        } else {
            runtimeCompareValues(lhs.key, rhs.key)
        }
        if comparison != 0 {
            return descending ? comparison > 0 : comparison < 0
        }
        return lhs.offset < rhs.offset
    }
    return sorted.map { (offset: $0.offset, element: $0.element) }
}

/// `kk_list_max{Of,With,OfWith}` / `kk_list_min{Of,With,OfWith}`
/// (and `OrNull` variants) — STDLIB-301b/c/d.
///
/// Split out from `RuntimeCollectionHOF.swift` to keep each runtime
/// source scoped to a single collection HOF concern.

private enum RuntimeCollectionExtremumDirection {
    case maximum
    case minimum

    func isBetter(_ comparison: Int) -> Bool {
        switch self {
        case .maximum:
            comparison > 0
        case .minimum:
            comparison < 0
        }
    }
}

private enum RuntimeCollectionEmptyExtremumResult {
    case throwNoSuchElement
    case nullSentinel

    func value(outThrown: UnsafeMutablePointer<Int>?) -> Int {
        switch self {
        case .throwNoSuchElement:
            handleCollectionLambdaThrow(
                runtimeAllocateNoSuchElementException(message: "List is empty."),
                outThrown
            )
        case .nullSentinel:
            runtimeNullSentinelInt
        }
    }
}

private func runtimeCollectionListOrPanic(_ listRaw: Int, functionName: StaticString) -> RuntimeListBox {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(functionName, "list")
    }
    return list
}

private func runtimeListExtremumOf(
    listRaw: Int,
    fnPtr: Int,
    closureRaw: Int,
    direction: RuntimeCollectionExtremumDirection,
    emptyResult: RuntimeCollectionEmptyExtremumResult,
    functionName: StaticString,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let list = runtimeCollectionListOrPanic(listRaw, functionName: functionName)
    guard !list.elements.isEmpty else {
        return emptyResult.value(outThrown: outThrown)
    }
    var thrown = 0
    var bestValue = runtimeInvokeCollectionLambda1(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        value: list.elements[0],
        outThrown: &thrown
    )
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for elem in list.elements.dropFirst() {
        thrown = 0
        let value = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: elem,
            outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if direction.isBetter(runtimeCompareValues(value, bestValue)) {
            bestValue = value
        }
    }
    return bestValue
}

private func runtimeListExtremumWith(
    listRaw: Int,
    fnPtr: Int,
    closureRaw: Int,
    direction: RuntimeCollectionExtremumDirection,
    emptyResult: RuntimeCollectionEmptyExtremumResult,
    functionName: StaticString,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let list = runtimeCollectionListOrPanic(listRaw, functionName: functionName)
    guard !list.elements.isEmpty else {
        return emptyResult.value(outThrown: outThrown)
    }
    let comparatorInvoke = runtimeSortedWithComparatorInvoke(fnPtr: fnPtr, closureRaw: closureRaw)
    var bestElem = list.elements[0]
    for elem in list.elements.dropFirst() {
        var thrown = 0
        let cmp = comparatorInvoke(elem, bestElem, &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if direction.isBetter(cmp) {
            bestElem = elem
        }
    }
    return bestElem
}

private func runtimeListExtremumOfWith(
    listRaw: Int,
    cmpFnPtr: Int,
    cmpClosureRaw: Int,
    selFnPtr: Int,
    selClosureRaw: Int,
    direction: RuntimeCollectionExtremumDirection,
    emptyResult: RuntimeCollectionEmptyExtremumResult,
    functionName: StaticString,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let list = runtimeCollectionListOrPanic(listRaw, functionName: functionName)
    guard !list.elements.isEmpty else {
        return emptyResult.value(outThrown: outThrown)
    }
    var thrown = 0
    var bestValue = runtimeInvokeCollectionLambda1(
        fnPtr: selFnPtr,
        closureRaw: selClosureRaw,
        value: list.elements[0],
        outThrown: &thrown
    )
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    let comparatorInvoke = runtimeSortedWithComparatorInvoke(fnPtr: cmpFnPtr, closureRaw: cmpClosureRaw)
    for elem in list.elements.dropFirst() {
        thrown = 0
        let value = runtimeInvokeCollectionLambda1(
            fnPtr: selFnPtr,
            closureRaw: selClosureRaw,
            value: elem,
            outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        thrown = 0
        let cmp = comparatorInvoke(value, bestValue, &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if direction.isBetter(cmp) {
            bestValue = value
        }
    }
    return bestValue
}
@_cdecl("kk_list_sortedBy_primitive")
public func kk_list_sortedBy_primitive(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ kindRaw: Int32, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard let sorted = runtimeSortByElements(
        list.elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        descending: false,
        primitiveKind: runtimePrimitiveCompareKindFromRaw(kindRaw),
        outThrown: outThrown
    ) else {
        return handleCollectionLambdaThrow(outThrown?.pointee ?? 0, outThrown)
    }
    return registerRuntimeObject(RuntimeListBox(elements: sorted.map(\.element)))
}

@_cdecl("kk_list_sortedByDescending_primitive")
public func kk_list_sortedByDescending_primitive(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ kindRaw: Int32, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard let sorted = runtimeSortByElements(
        list.elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        descending: true,
        primitiveKind: runtimePrimitiveCompareKindFromRaw(kindRaw),
        outThrown: outThrown
    ) else {
        return handleCollectionLambdaThrow(outThrown?.pointee ?? 0, outThrown)
    }
    return registerRuntimeObject(RuntimeListBox(elements: sorted.map(\.element)))
}

@_cdecl("kk_list_maxOrNull")
public func kk_list_maxOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard let first = list.elements.first else {
        return runtimeNullSentinelInt
    }
    var best = first
    for elem in list.elements.dropFirst() where runtimeCompareValues(elem, best) > 0 {
        best = elem
    }
    return best
}

@_cdecl("kk_list_minOrNull")
public func kk_list_minOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard let first = list.elements.first else {
        return runtimeNullSentinelInt
    }
    var best = first
    for elem in list.elements.dropFirst() where runtimeCompareValues(elem, best) < 0 {
        best = elem
    }
    return best
}

@_cdecl("kk_list_min")
public func kk_list_min(_ listRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard let first = list.elements.first else {
        return handleCollectionLambdaThrow(
            runtimeAllocateNoSuchElementException(message: "List is empty."),
            outThrown
        )
    }
    var best = first
    for elem in list.elements.dropFirst() where runtimeCompareValues(elem, best) < 0 {
        best = elem
    }
    return best
}

@_cdecl("kk_list_maxByOrNull")
public func kk_list_maxByOrNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return runtimeNullSentinelInt
    }
    var bestElem = list.elements[0]
    var thrown = 0
    var bestKey = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: bestElem, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for elem in list.elements.dropFirst() {
        thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if runtimeCompareValues(key, bestKey) > 0 {
            bestElem = elem
            bestKey = key
        }
    }
    return bestElem
}

@_cdecl("kk_list_maxBy")
public func kk_list_maxBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return handleCollectionLambdaThrow(runtimeAllocateNoSuchElementException(message: "List is empty."), outThrown)
    }
    var bestElem = list.elements[0]
    var thrown = 0
    var bestKey = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: bestElem, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for elem in list.elements.dropFirst() {
        thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if runtimeCompareValues(key, bestKey) > 0 {
            bestElem = elem
            bestKey = key
        }
    }
    return bestElem
}

@_cdecl("kk_list_minByOrNull")
public func kk_list_minByOrNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return runtimeNullSentinelInt
    }
    var bestElem = list.elements[0]
    var thrown = 0
    var bestKey = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: bestElem, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for elem in list.elements.dropFirst() {
        thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if runtimeCompareValues(key, bestKey) < 0 {
            bestElem = elem
            bestKey = key
        }
    }
    return bestElem
}

@_cdecl("kk_list_minBy")
public func kk_list_minBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return handleCollectionLambdaThrow(runtimeAllocateNoSuchElementException(message: "List is empty."), outThrown)
    }
    var bestElem = list.elements[0]
    var thrown = 0
    var bestKey = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: bestElem, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for elem in list.elements.dropFirst() {
        thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if runtimeCompareValues(key, bestKey) < 0 {
            bestElem = elem
            bestKey = key
        }
    }
    return bestElem
}

@_cdecl("kk_list_maxOfOrNull")
public func kk_list_maxOfOrNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return runtimeNullSentinelInt
    }
    var thrown = 0
    var bestValue = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: list.elements[0], outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for elem in list.elements.dropFirst() {
        thrown = 0
        let value = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if runtimeCompareValues(value, bestValue) > 0 {
            bestValue = value
        }
    }
    return bestValue
}

@_cdecl("kk_list_minOfOrNull")
public func kk_list_minOfOrNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return runtimeNullSentinelInt
    }
    var thrown = 0
    var bestValue = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: list.elements[0], outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for elem in list.elements.dropFirst() {
        thrown = 0
        let value = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if runtimeCompareValues(value, bestValue) < 0 {
            bestValue = value
        }
    }
    return bestValue
}

@_cdecl("kk_list_sortedDescending")
public func kk_list_sortedDescending(_ listRaw: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let sorted = elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 {
            return comparison > 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    return registerRuntimeObject(RuntimeListBox(elements: sorted))
}

@_cdecl("kk_list_sortedByDescending")
public func kk_list_sortedByDescending(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var keys: [Int] = []
    keys.reserveCapacity(list.elements.count)
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        keys.append(key)
    }
    let indexed = list.elements.enumerated().map { ($0.offset, $0.element, keys[$0.offset]) }
    let sorted = indexed.sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.2, rhs.2)
        if comparison != 0 { return comparison > 0 }
        return lhs.0 < rhs.0
    }.map { $0.1 }
    return registerRuntimeObject(RuntimeListBox(elements: sorted))
}

@_cdecl("kk_list_sortedWith")
public func kk_list_sortedWith(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    let comparatorInvoke = runtimeSortedWithComparatorInvoke(fnPtr: fnPtr, closureRaw: closureRaw)
    var hadThrow = false
    var indexed = list.elements.enumerated().map { ($0.offset, $0.element) }
    indexed.sort { lhs, rhs in
        guard !hadThrow else { return false }
        var thrown = 0
        let result = comparatorInvoke(lhs.1, rhs.1, &thrown)
        if thrown != 0 { _ = handleCollectionLambdaThrow(thrown, outThrown); hadThrow = true; return false }
        if result != 0 { return result < 0 }
        return lhs.0 < rhs.0
    }
    if hadThrow { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    return registerRuntimeObject(RuntimeListBox(elements: indexed.map { $0.1 }))
}

@_cdecl("kk_mutable_list_sort")
public func kk_mutable_list_sort(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let indexed = list.elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 { return comparison < 0 }
        return lhs.offset < rhs.offset
    }.map(\.element)
    for i in 0 ..< indexed.count {
        list.elements[i] = indexed[i]
    }
    return 0
}

@_cdecl("kk_mutable_list_sort_primitive")
public func kk_mutable_list_sort_primitive(_ listRaw: Int, _ kindRaw: Int32) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let sorted = runtimeSortElements(list.elements, descending: false, primitiveKind: runtimePrimitiveCompareKindFromRaw(kindRaw))
    for i in 0 ..< sorted.count {
        list.elements[i] = sorted[i]
    }
    return 0
}

@_cdecl("kk_mutable_list_sortWith")
public func kk_mutable_list_sortWith(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let comparatorInvoke = runtimeSortedWithComparatorInvoke(fnPtr: fnPtr, closureRaw: closureRaw)
    var hadThrow = false
    let sorted = list.elements.enumerated().sorted { lhs, rhs in
        guard !hadThrow else { return false }
        var thrown = 0
        let result = comparatorInvoke(lhs.element, rhs.element, &thrown)
        if thrown != 0 {
            _ = handleCollectionLambdaThrow(thrown, outThrown)
            hadThrow = true
            return false
        }
        if result != 0 { return result < 0 }
        return lhs.offset < rhs.offset
    }.map(\.element)
    if hadThrow { return 0 }
    for i in 0 ..< sorted.count {
        list.elements[i] = sorted[i]
    }
    return 0
}

@_cdecl("kk_mutable_list_sortBy")
public func kk_mutable_list_sortBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    guard let sorted = runtimeSortByElements(
        list.elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        descending: false,
        primitiveKind: nil,
        outThrown: outThrown
    ) else {
        return handleCollectionLambdaThrow(outThrown?.pointee ?? 0, outThrown)
    }
    for i in 0 ..< sorted.count {
        list.elements[i] = sorted[i].element
    }
    return 0
}

@_cdecl("kk_mutable_list_sortBy_primitive")
public func kk_mutable_list_sortBy_primitive(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ kindRaw: Int32, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    guard let sorted = runtimeSortByElements(
        list.elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        descending: false,
        primitiveKind: runtimePrimitiveCompareKindFromRaw(kindRaw),
        outThrown: outThrown
    ) else {
        return handleCollectionLambdaThrow(outThrown?.pointee ?? 0, outThrown)
    }
    for i in 0 ..< sorted.count {
        list.elements[i] = sorted[i].element
    }
    return 0
}

@_cdecl("kk_mutable_list_sortByDescending")
public func kk_mutable_list_sortByDescending(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    guard let sorted = runtimeSortByElements(
        list.elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        descending: true,
        primitiveKind: nil,
        outThrown: outThrown
    ) else {
        return handleCollectionLambdaThrow(outThrown?.pointee ?? 0, outThrown)
    }
    for i in 0 ..< sorted.count {
        list.elements[i] = sorted[i].element
    }
    return 0
}

@_cdecl("kk_mutable_list_sortByDescending_primitive")
public func kk_mutable_list_sortByDescending_primitive(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ kindRaw: Int32, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    guard let sorted = runtimeSortByElements(
        list.elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        descending: true,
        primitiveKind: runtimePrimitiveCompareKindFromRaw(kindRaw),
        outThrown: outThrown
    ) else {
        return handleCollectionLambdaThrow(outThrown?.pointee ?? 0, outThrown)
    }
    for i in 0 ..< sorted.count {
        list.elements[i] = sorted[i].element
    }
    return 0
}

@_cdecl("kk_mutable_list_sortDescending")
public func kk_mutable_list_sortDescending(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let indexed = list.elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 { return comparison > 0 }  // Descending order
        return lhs.offset < rhs.offset
    }.map(\.element)
    for i in 0 ..< indexed.count {
        list.elements[i] = indexed[i]
    }
    return 0
}

@_cdecl("kk_mutable_list_sortDescending_primitive")
public func kk_mutable_list_sortDescending_primitive(_ listRaw: Int, _ kindRaw: Int32) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let sorted = runtimeSortElements(list.elements, descending: true, primitiveKind: runtimePrimitiveCompareKindFromRaw(kindRaw))
    for i in 0 ..< sorted.count {
        list.elements[i] = sorted[i]
    }
    return 0
}

@_cdecl("kk_list_maxOf")
public func kk_list_maxOf(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumOf(
        listRaw: listRaw,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        direction: .maximum,
        emptyResult: .throwNoSuchElement,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_minOf")
public func kk_list_minOf(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumOf(
        listRaw: listRaw,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        direction: .minimum,
        emptyResult: .throwNoSuchElement,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_maxWithOrNull")
public func kk_list_maxWithOrNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumWith(
        listRaw: listRaw,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        direction: .maximum,
        emptyResult: .nullSentinel,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_maxWith")
public func kk_list_maxWith(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumWith(
        listRaw: listRaw,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        direction: .maximum,
        emptyResult: .throwNoSuchElement,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_minWithOrNull")
public func kk_list_minWithOrNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumWith(
        listRaw: listRaw,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        direction: .minimum,
        emptyResult: .nullSentinel,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_minWith")
public func kk_list_minWith(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumWith(
        listRaw: listRaw,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        direction: .minimum,
        emptyResult: .throwNoSuchElement,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_maxOfWithOrNull")
public func kk_list_maxOfWithOrNull(_ listRaw: Int, _ cmpFnPtr: Int, _ cmpClosureRaw: Int, _ selFnPtr: Int, _ selClosureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumOfWith(
        listRaw: listRaw,
        cmpFnPtr: cmpFnPtr,
        cmpClosureRaw: cmpClosureRaw,
        selFnPtr: selFnPtr,
        selClosureRaw: selClosureRaw,
        direction: .maximum,
        emptyResult: .nullSentinel,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_maxOfWith")
public func kk_list_maxOfWith(_ listRaw: Int, _ cmpFnPtr: Int, _ cmpClosureRaw: Int, _ selFnPtr: Int, _ selClosureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumOfWith(
        listRaw: listRaw,
        cmpFnPtr: cmpFnPtr,
        cmpClosureRaw: cmpClosureRaw,
        selFnPtr: selFnPtr,
        selClosureRaw: selClosureRaw,
        direction: .maximum,
        emptyResult: .throwNoSuchElement,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_minOfWithOrNull")
public func kk_list_minOfWithOrNull(_ listRaw: Int, _ cmpFnPtr: Int, _ cmpClosureRaw: Int, _ selFnPtr: Int, _ selClosureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumOfWith(
        listRaw: listRaw,
        cmpFnPtr: cmpFnPtr,
        cmpClosureRaw: cmpClosureRaw,
        selFnPtr: selFnPtr,
        selClosureRaw: selClosureRaw,
        direction: .minimum,
        emptyResult: .nullSentinel,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_minOfWith")
public func kk_list_minOfWith(_ listRaw: Int, _ cmpFnPtr: Int, _ cmpClosureRaw: Int, _ selFnPtr: Int, _ selClosureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeListExtremumOfWith(
        listRaw: listRaw,
        cmpFnPtr: cmpFnPtr,
        cmpClosureRaw: cmpClosureRaw,
        selFnPtr: selFnPtr,
        selClosureRaw: selClosureRaw,
        direction: .minimum,
        emptyResult: .throwNoSuchElement,
        functionName: #function,
        outThrown: outThrown
    )
}

@_cdecl("kk_list_sorted")
public func kk_list_sorted(_ listRaw: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let sorted = elements.enumerated().sorted { lhs, rhs in
        let comparison = runtimeCompareValues(lhs.element, rhs.element)
        if comparison != 0 {
            return comparison < 0
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    return registerRuntimeObject(RuntimeListBox(elements: sorted))
}

@_cdecl("kk_list_sorted_primitive")
public func kk_list_sorted_primitive(_ listRaw: Int, _ kindRaw: Int32) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let sorted = runtimeSortElements(listBox.elements, descending: false, primitiveKind: runtimePrimitiveCompareKindFromRaw(kindRaw))
    return registerRuntimeObject(RuntimeListBox(elements: sorted))
}

@_cdecl("kk_list_sortedDescending_primitive")
public func kk_list_sortedDescending_primitive(_ listRaw: Int, _ kindRaw: Int32) -> Int {
    guard let listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let sorted = runtimeSortElements(listBox.elements, descending: true, primitiveKind: runtimePrimitiveCompareKindFromRaw(kindRaw))
    return registerRuntimeObject(RuntimeListBox(elements: sorted))
}

@_cdecl("kk_list_max")
public func kk_list_max(_ listRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let result = kk_list_maxOrNull(listRaw)
    guard result != runtimeNullSentinelInt else {
        return handleCollectionLambdaThrow(runtimeAllocateNoSuchElementException(message: "List is empty."), outThrown)
    }
    return result
}

#endif
