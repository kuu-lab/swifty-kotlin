// String higher-order functions (iterator, filter, map, count, any, all, none,
// chunked, windowed, zip, commonPrefix/Suffix, and advanced HOFs).
// Split out from `RuntimeStringStdlib.swift`.

import Foundation

private func runtimeStringHOFElementValue(_ raw: Int) -> RuntimeValue {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return RuntimeValue(raw: maybeUnbox(raw))
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return RuntimeValue(raw: maybeUnbox(raw))
    }
    if let charBox = tryCast(ptr, to: RuntimeCharBox.self) {
        return RuntimeValue(charScalar: charBox.value)
    }
    if let stringBox = tryCast(ptr, to: RuntimeStringBox.self) {
        return runtimeStringHOFStringValue(stringBox.value)
    }
    return RuntimeValue(raw: maybeUnbox(raw))
}

private func runtimeStringHOFStringValue(_ value: String) -> RuntimeValue {
    var length = 0
    var byteCount = 0
    var hash = 0
    let data = runtimeRegisterFlatString(
        value,
        outLength: &length,
        outByteCount: &byteCount,
        outHash: &hash
    )
    guard let data else {
        return RuntimeValue(raw: 0)
    }
    return RuntimeValue(
        stringData: Int(bitPattern: data),
        length: length,
        byteCount: byteCount,
        hash: hash
    )
}

// MARK: - STDLIB-189: String iterator and HOF (filter, map, count, any, all, none)

@_cdecl("kk_string_iterator")
public func kk_string_iterator(_ strRaw: Int) -> Int {
    let charRaws = runtimeStringUTF16CodeUnits(strRaw).map { Int($0) }
    let box = RuntimeStringIteratorBox(charRaws: charRaws)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

@_cdecl("kk_string_iterator_hasNext")
public func kk_string_iterator_hasNext(_ iterRaw: Int) -> Int {
    guard let iter = runtimeStringIteratorBox(from: iterRaw) else { return 0 }
    return iter.index < iter.charRaws.count ? 1 : 0
}

@_cdecl("kk_string_iterator_next")
public func kk_string_iterator_next(_ iterRaw: Int) -> Int {
    guard let iter = runtimeStringIteratorBox(from: iterRaw) else { return 0 }
    guard iter.index < iter.charRaws.count else { return 0 }
    let value = iter.charRaws[iter.index]
    iter.index += 1
    return value
}

@_cdecl("kk_string_filter")
public func kk_string_filter(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return runtimeMakeStringRaw(runtimeStringFromRawOrPanic(strRaw, caller: #function)) }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var filtered: [UnicodeScalar] = []
    for scalar in scalars {
        var thrown = 0
        let result = lambda(closureRaw, Int(scalar.value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        if result != 0 { filtered.append(scalar) }
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(filtered))
}

@_cdecl("kk_string_filter_flat")
public func kk_string_filter_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_filter(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_map")
public func kk_string_map(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return strRaw }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var mappedElements: [RuntimeValue] = []
    for scalar in scalars {
        var thrown = 0
        let result = lambda(closureRaw, Int(scalar.value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        mappedElements.append(runtimeStringHOFElementValue(result))
    }
    return registerRuntimeObject(RuntimeListBox(values: mappedElements))
}

@_cdecl("kk_string_map_flat")
public func kk_string_map_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_map(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_count")
public func kk_string_count(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    if fnPtr == 0 { return scalars.count }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var count = 0
    for scalar in scalars {
        var thrown = 0
        let result = lambda(closureRaw, Int(scalar.value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if result != 0 { count += 1 }
    }
    return count
}

@_cdecl("kk_string_count_flat")
public func kk_string_count_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_count(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_any")
public func kk_string_any(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    if fnPtr == 0 { return scalars.isEmpty ? 0 : 1 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for scalar in scalars {
        var thrown = 0
        let result = lambda(closureRaw, Int(scalar.value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if result != 0 { return 1 }
    }
    return 0
}

@_cdecl("kk_string_any_flat")
public func kk_string_any_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_any(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_all")
public func kk_string_all(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    if fnPtr == 0 { return 1 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for scalar in scalars {
        var thrown = 0
        let result = lambda(closureRaw, Int(scalar.value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if result == 0 { return 0 }
    }
    return 1
}

@_cdecl("kk_string_all_flat")
public func kk_string_all_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_all(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_none")
public func kk_string_none(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    if fnPtr == 0 { return scalars.isEmpty ? 1 : 0 }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for scalar in scalars {
        var thrown = 0
        let result = lambda(closureRaw, Int(scalar.value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return 0 }
        if result != 0 { return 0 }
    }
    return 1
}

@_cdecl("kk_string_none_flat")
public func kk_string_none_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_none(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

// MARK: - STDLIB-316: String.chunked / String.windowed

func runtimeStringChunkValues(_ source: String, size: Int) -> [RuntimeValue] {
    guard size > 0 else { return [] }
    let scalars = Array(source.unicodeScalars)
    var chunks: [RuntimeValue] = []
    var i = 0
    while i < scalars.count {
        let end = Swift.min(i + size, scalars.count)
        chunks.append(runtimeStringHOFStringValue(runtimeStringFromScalars(scalars[i ..< end])))
        i = end
    }
    return chunks
}

func runtimeStringChunkedList(_ source: String, size: Int) -> Int {
    registerRuntimeObject(RuntimeListBox(values: runtimeStringChunkValues(source, size: size)))
}

func runtimeStringChunkedSequence(_ source: String, size: Int) -> Int {
    registerRuntimeObject(RuntimeSequenceBox(steps: [.valueSource(values: runtimeStringChunkValues(source, size: size))]))
}

@_cdecl("kk_string_chunked")
public func kk_string_chunked(_ strRaw: Int, _ size: Int) -> Int {
    runtimeStringChunkedList(runtimeStringFromRawOrPanic(strRaw, caller: #function), size: size)
}

@_cdecl("kk_string_chunked_sequence")
public func kk_string_chunked_sequence(_ strRaw: Int, _ size: Int) -> Int {
    runtimeStringChunkedSequence(runtimeStringFromRawOrPanic(strRaw, caller: #function), size: size)
}

@_cdecl("kk_string_chunked_sequence_transform")
public func kk_string_chunked_sequence_transform(
    _ strRaw: Int,
    _ size: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let chunkSize = max(1, size)
    let scalars = Array(source.unicodeScalars)
    let estimatedChunks = scalars.isEmpty ? 0 : (scalars.count + chunkSize - 1) / chunkSize
    var results: [RuntimeValue] = []
    results.reserveCapacity(estimatedChunks)
    var index = 0
    while index < scalars.count {
        let end = Swift.min(index + chunkSize, scalars.count)
        let chunkRaw = runtimeMakeStringRaw(runtimeStringFromScalars(scalars[index ..< end]))
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: chunkRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        results.append(runtimeStringHOFElementValue(transformed))
        index = end
    }
    return registerRuntimeObject(RuntimeSequenceBox(steps: [.valueSource(values: results)]))
}

@_cdecl("kk_string_windowed_default")
public func kk_string_windowed_default(_ strRaw: Int, _ size: Int) -> Int {
    return kk_string_windowed(strRaw, size, 1)
}

func runtimeStringWindowedValues(_ source: String, size: Int, step: Int) -> [RuntimeValue] {
    guard size > 0, step > 0 else { return [] }
    let scalars = Array(source.unicodeScalars)
    var windows: [RuntimeValue] = []
    var i = 0
    while i + size <= scalars.count {
        windows.append(runtimeStringHOFStringValue(runtimeStringFromScalars(scalars[i ..< i + size])))
        i += step
    }
    return windows
}

func runtimeStringWindowedPartialValues(_ source: String, size: Int, step: Int, partialWindows: Int) -> [RuntimeValue] {
    let clampedSize = Swift.max(1, size)
    let clampedStep = Swift.max(1, step)
    let scalars = Array(source.unicodeScalars)
    let partial = partialWindows != 0
    var windows: [RuntimeValue] = []
    var i = 0
    while i < scalars.count {
        let end = Swift.min(i + clampedSize, scalars.count)
        if !partial && end - i < clampedSize { break }
        windows.append(runtimeStringHOFStringValue(runtimeStringFromScalars(scalars[i ..< end])))
        i += clampedStep
    }
    return windows
}

func runtimeStringWindowedList(_ source: String, size: Int, step: Int) -> Int {
    registerRuntimeObject(RuntimeListBox(values: runtimeStringWindowedValues(source, size: size, step: step)))
}

func runtimeStringWindowedPartialList(_ source: String, size: Int, step: Int, partialWindows: Int) -> Int {
    registerRuntimeObject(RuntimeListBox(values: runtimeStringWindowedPartialValues(source, size: size, step: step, partialWindows: partialWindows)))
}

func runtimeStringWindowedSequencePartial(_ source: String, size: Int, step: Int, partialWindows: Int) -> Int {
    registerRuntimeObject(RuntimeSequenceBox(steps: [.valueSource(values: runtimeStringWindowedPartialValues(source, size: size, step: step, partialWindows: partialWindows))]))
}

@_cdecl("kk_string_windowed")
public func kk_string_windowed(_ strRaw: Int, _ size: Int, _ step: Int) -> Int {
    runtimeStringWindowedList(runtimeStringFromRawOrPanic(strRaw, caller: #function), size: size, step: step)
}

@_cdecl("kk_string_windowed_partial")
public func kk_string_windowed_partial(_ strRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    runtimeStringWindowedPartialList(runtimeStringFromRawOrPanic(strRaw, caller: #function), size: size, step: step, partialWindows: partialWindows)
}

@_cdecl("kk_string_windowedSequence_partial")
public func kk_string_windowedSequence_partial(_ strRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int) -> Int {
    runtimeStringWindowedSequencePartial(runtimeStringFromRawOrPanic(strRaw, caller: #function), size: size, step: step, partialWindows: partialWindows)
}

@_cdecl("kk_string_windowedSequence_transform")
public func kk_string_windowedSequence_transform(
    _ strRaw: Int,
    _ size: Int,
    _ step: Int,
    _ partialWindows: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let clampedSize = max(1, size)
    let clampedStep = max(1, step)
    let scalars = Array(source.unicodeScalars)
    let partial = partialWindows != 0
    var results: [RuntimeValue] = []
    var i = 0
    while i < scalars.count {
        let end = min(i + clampedSize, scalars.count)
        if !partial && end - i < clampedSize { break }
        let windowRaw = runtimeMakeStringRaw(runtimeStringFromScalars(scalars[i ..< end]))
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: windowRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
        results.append(runtimeStringHOFElementValue(transformed))
        i += clampedStep
    }
    return registerRuntimeObject(RuntimeSequenceBox(steps: [.valueSource(values: results)]))
}

// MARK: - STDLIB-316: String.zipWithNext()

@_cdecl("kk_string_zipWithNext")
public func kk_string_zipWithNext(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRaw(strRaw) ?? ""
    guard source.unicodeScalars.count >= 2 else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let scalars = Array(source.unicodeScalars)
    var pairs: [Int] = []
    for i in 0 ..< scalars.count - 1 {
        pairs.append(runtimePairNew(
            firstValue: RuntimeValue(charScalar: Int(scalars[i].value)),
            secondValue: RuntimeValue(charScalar: Int(scalars[i + 1].value))
        ))
    }
    return registerRuntimeObject(RuntimeListBox(elements: pairs))
}

@_cdecl("kk_string_zipWithNext_flat")
public func kk_string_zipWithNext_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    kk_string_zipWithNext(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("kk_string_zipWithNextTransform")
public func kk_string_zipWithNextTransform(_ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRaw(strRaw) ?? ""
    let scalars = Array(source.unicodeScalars)
    guard scalars.count >= 2 else {
        return registerRuntimeObject(RuntimeListBox(values: []))
    }
    var results: [RuntimeValue] = []
    results.reserveCapacity(scalars.count - 1)
    for i in 0 ..< scalars.count - 1 {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: Int(scalars[i].value),
            rhs: Int(scalars[i + 1].value),
            outThrown: &thrown
        )
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return 0
        }
        results.append(runtimeStringHOFElementValue(result))
    }
    return registerRuntimeObject(RuntimeListBox(values: results))
}

@_cdecl("kk_string_zipWithNextTransform_flat")
public func kk_string_zipWithNextTransform_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_zipWithNextTransform(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

// MARK: - STDLIB-TEXT-FN-116: CharSequence.zip(other) / zip(other, transform)

@_cdecl("kk_string_zip")
public func kk_string_zip(_ strRaw: Int, _ otherRaw: Int) -> Int {
    let sourceCodeUnits = runtimeStringUTF16CodeUnits(strRaw)
    let otherCodeUnits = runtimeStringUTF16CodeUnits(otherRaw)
    let count = min(sourceCodeUnits.count, otherCodeUnits.count)
    var pairs: [Int] = []
    pairs.reserveCapacity(count)
    for i in 0 ..< count {
        pairs.append(runtimePairNew(
            firstValue: RuntimeValue(charScalar: Int(sourceCodeUnits[i])),
            secondValue: RuntimeValue(charScalar: Int(otherCodeUnits[i]))
        ))
    }
    return registerRuntimeObject(RuntimeListBox(elements: pairs))
}

@_cdecl("kk_string_zip_flat")
public func kk_string_zip_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ otherData: UnsafePointer<UInt8>?,
    _ otherLength: Int,
    _ otherByteCount: Int,
    _ otherHash: Int
) -> Int {
    kk_string_zip(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(otherData, otherLength, otherByteCount, otherHash)
    )
}

@_cdecl("kk_string_zipTransform")
public func kk_string_zipTransform(
    _ strRaw: Int,
    _ otherRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let sourceCodeUnits = runtimeStringUTF16CodeUnits(strRaw)
    let otherCodeUnits = runtimeStringUTF16CodeUnits(otherRaw)
    let count = min(sourceCodeUnits.count, otherCodeUnits.count)
    var results: [RuntimeValue] = []
    results.reserveCapacity(count)
    for i in 0 ..< count {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: kk_box_char(Int(sourceCodeUnits[i])),
            rhs: kk_box_char(Int(otherCodeUnits[i])),
            outThrown: &thrown
        )
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return 0
        }
        results.append(runtimeStringHOFElementValue(result))
    }
    return registerRuntimeObject(RuntimeListBox(values: results))
}

@_cdecl("kk_string_zipTransform_flat")
public func kk_string_zipTransform_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ otherData: UnsafePointer<UInt8>?,
    _ otherLength: Int,
    _ otherByteCount: Int,
    _ otherHash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_zipTransform(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(otherData, otherLength, otherByteCount, otherHash),
        fnPtr,
        closureRaw,
        outThrown
    )
}

// MARK: - STDLIB-192: equals(other, ignoreCase)

@_cdecl("kk_string_equalsIgnoreCase")
public func kk_string_equalsIgnoreCase(_ strRaw: Int, _ otherRaw: Int, _ ignoreCaseRaw: Int) -> Int {
    if otherRaw == runtimeNullSentinelInt {
        return kk_box_bool(0)
    }
    let cmp = kk_string_compareToIgnoreCase(strRaw, otherRaw, ignoreCaseRaw)
    return kk_box_bool(cmp == 0 ? 1 : 0)
}

@_cdecl("kk_string_equals")
public func kk_string_equals(_ strRaw: Int, _ otherRaw: Int) -> Int {
    if otherRaw == runtimeNullSentinelInt {
        return kk_box_bool(0)
    }
    return kk_box_bool(kk_string_compareTo_member(strRaw, otherRaw) == 0 ? 1 : 0)
}

@_cdecl("kk_string_equals_flat")
public func kk_string_equals_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ otherData: UnsafePointer<UInt8>?,
    _ otherLength: Int,
    _ otherByteCount: Int,
    _ otherHash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    let other = runtimeStringFromFlatFields(data: otherData, length: otherLength, byteCount: otherByteCount, hash: otherHash)
    return source == other ? 1 : 0
}

// MARK: - STDLIB-HOF-023: Advanced String Higher-Order Functions

@_cdecl("kk_string_mapIndexed")
public func kk_string_mapIndexed(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return strRaw }
    var mappedElements: [RuntimeValue] = []
    for (index, scalar) in scalars.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: index,
            rhs: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        mappedElements.append(runtimeStringHOFElementValue(result))
    }
    return registerRuntimeObject(RuntimeListBox(values: mappedElements))
}

@_cdecl("kk_string_mapNotNull")
public func kk_string_mapNotNull(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return strRaw }
    var mappedElements: [RuntimeValue] = []
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        if result != runtimeNullSentinelInt {
            mappedElements.append(runtimeStringHOFElementValue(result))
        }
    }
    return registerRuntimeObject(RuntimeListBox(values: mappedElements))
}

@_cdecl("kk_string_mapNotNull_flat")
public func kk_string_mapNotNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_mapNotNull(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_mapIndexed_flat")
public func kk_string_mapIndexed_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_mapIndexed(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}


@_cdecl("kk_string_firstNotNullOf")
public func kk_string_firstNotNullOf(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
        if result != 0, let normalized = runtimeMapNotNullResultValue(result) {
            return normalized
        }
    }
    outThrown?.pointee = runtimeAllocateThrowable(
        message: "NoSuchElementException: No element of the char sequence was transformed to a non-null value."
    )
    return 0
}

@_cdecl("kk_string_firstNotNullOf_flat")
public func kk_string_firstNotNullOf_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_firstNotNullOf(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_firstNotNullOfOrNull")
public func kk_string_firstNotNullOfOrNull(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            return runtimeNullSentinelInt
        }
        if result != 0, let normalized = runtimeMapNotNullResultValue(result) {
            return normalized
        }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_string_firstNotNullOfOrNull_flat")
public func kk_string_firstNotNullOfOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_firstNotNullOfOrNull(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

// MARK: - STDLIB-TEXT-FN-046: CharSequence.reduce

@_cdecl("kk_string_reduce")
public func kk_string_reduce(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard !codeUnits.isEmpty else {
        return handleCollectionLambdaThrow(
            runtimeAllocateThrowable(message: "Empty char sequence can't be reduced."),
            outThrown
        )
    }
    var acc = Int(codeUnits[0])
    guard codeUnits.count > 1 else {
        return acc
    }
    for index in 1 ..< codeUnits.count {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: acc,
            rhs: Int(codeUnits[index]),
            outThrown: &thrown
        ))
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
    }
    return acc
}

// MARK: - STDLIB-TEXT-FN-048: CharSequence.reduceIndexedOrNull

@_cdecl("kk_string_reduceIndexedOrNull")
public func kk_string_reduceIndexedOrNull(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard !codeUnits.isEmpty else {
        return runtimeNullSentinelInt
    }
    var acc = Int(codeUnits[0])
    guard codeUnits.count > 1 else {
        return acc
    }
    for index in 1 ..< codeUnits.count {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda3(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            arg1: index,
            arg2: acc,
            arg3: Int(codeUnits[index]),
            outThrown: &thrown
        ))
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
    }
    return acc
}

// MARK: - STDLIB-TEXT-FN-049: CharSequence.reduceOrNull

@_cdecl("kk_string_reduceOrNull")
public func kk_string_reduceOrNull(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard !codeUnits.isEmpty else {
        return runtimeNullSentinelInt
    }
    var acc = Int(codeUnits[0])
    guard codeUnits.count > 1 else {
        return acc
    }
    for index in 1 ..< codeUnits.count {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: acc,
            rhs: Int(codeUnits[index]),
            outThrown: &thrown
        ))
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
    }
    return acc
}

@_cdecl("kk_string_reduceOrNull_flat")
public func kk_string_reduceOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_reduceOrNull(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_reduceRightIndexed")
public func kk_string_reduceRightIndexed(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard !scalars.isEmpty else {
        return handleCollectionLambdaThrow(
            runtimeAllocateThrowable(message: "Empty char sequence can't be reduced."),
            outThrown
        )
    }

    var acc = Int(scalars[scalars.count - 1].value)
    guard scalars.count > 1 else {
        return acc
    }

    for index in stride(from: scalars.count - 2, through: 0, by: -1) {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda3(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            arg1: index,
            arg2: Int(scalars[index].value),
            arg3: acc,
            outThrown: &thrown
        ))
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
    }
    return acc
}

@_cdecl("kk_string_reduceRightIndexed_flat")
public func kk_string_reduceRightIndexed_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_reduceRightIndexed(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_reduceRightIndexedOrNull")
public func kk_string_reduceRightIndexedOrNull(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard !scalars.isEmpty else {
        return runtimeNullSentinelInt
    }

    var acc = Int(scalars[scalars.count - 1].value)
    guard scalars.count > 1 else {
        return acc
    }

    for index in stride(from: scalars.count - 2, through: 0, by: -1) {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda3(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            arg1: index,
            arg2: Int(scalars[index].value),
            arg3: acc,
            outThrown: &thrown
        ))
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
    }
    return acc
}

@_cdecl("kk_string_reduceRightIndexedOrNull_flat")
public func kk_string_reduceRightIndexedOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_reduceRightIndexedOrNull(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_reduceRightOrNull")
public func kk_string_reduceRightOrNull(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard !scalars.isEmpty else {
        return runtimeNullSentinelInt
    }

    var acc = Int(scalars[scalars.count - 1].value)
    guard scalars.count > 1 else {
        return acc
    }

    for index in stride(from: scalars.count - 2, through: 0, by: -1) {
        var thrown = 0
        acc = maybeUnbox(runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: Int(scalars[index].value),
            rhs: acc,
            outThrown: &thrown
        ))
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
    }
    return acc
}

@_cdecl("kk_string_reduceRightOrNull_flat")
public func kk_string_reduceRightOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_reduceRightOrNull(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_sumBy")
public func kk_string_sumBy(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    var total = 0
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        total += maybeUnbox(result)
    }
    return total
}

@_cdecl("kk_string_sumBy_flat")
public func kk_string_sumBy_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_sumBy(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_sumByDouble")
public func kk_string_sumByDouble(
    _ strRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    var total = 0.0
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        total += kk_bits_to_double(result)
    }
    return kk_double_to_bits(total)
}

@_cdecl("kk_string_sumByDouble_flat")
public func kk_string_sumByDouble_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_sumByDouble(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_filterIndexed")
public func kk_string_filterIndexed(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return runtimeMakeStringRaw(runtimeStringFromRawOrPanic(strRaw, caller: #function)) }
    var filtered: [UnicodeScalar] = []
    for (index, scalar) in scalars.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: index,
            rhs: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        if result != 0 { filtered.append(scalar) }
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(filtered))
}

@_cdecl("kk_string_filterIndexed_flat")
public func kk_string_filterIndexed_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_filterIndexed(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_filterNot")
public func kk_string_filterNot(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return runtimeMakeStringRaw(runtimeStringFromRawOrPanic(strRaw, caller: #function)) }
    var filtered: [UnicodeScalar] = []
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        if result == 0 { filtered.append(scalar) }
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(filtered))
}

@_cdecl("kk_string_filterNot_flat")
public func kk_string_filterNot_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_filterNot(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_takeWhile")
public func kk_string_takeWhile(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return runtimeMakeStringRaw(runtimeStringFromRawOrPanic(strRaw, caller: #function)) }
    var taken: [UnicodeScalar] = []
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        if result == 0 { break }
        taken.append(scalar)
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(taken))
}

@_cdecl("kk_string_takeWhile_flat")
public func kk_string_takeWhile_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_takeWhile(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_takeLastWhile")
public func kk_string_takeLastWhile(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let codeUnits = runtimeStringUTF16CodeUnits(strRaw)
    guard fnPtr != 0 else { return runtimeMakeStringRaw(runtimeStringFromRawOrPanic(strRaw, caller: #function)) }
    var takenCount = 0
    for codeUnit in codeUnits.reversed() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(codeUnit),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        if result == 0 { break }
        takenCount += 1
    }
    return runtimeMakeStringRaw(String(decoding: codeUnits.suffix(takenCount), as: UTF16.self))
}

@_cdecl("kk_string_takeLastWhile_flat")
public func kk_string_takeLastWhile_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_takeLastWhile(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_dropWhile")
public func kk_string_dropWhile(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return runtimeMakeStringRaw(runtimeStringFromRawOrPanic(strRaw, caller: #function)) }
    var dropIndex = 0
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeMakeStringRaw("") }
        if result == 0 { break }
        dropIndex += 1
    }
    return runtimeMakeStringRaw(runtimeStringFromScalars(Array(scalars.dropFirst(dropIndex))))
}

@_cdecl("kk_string_dropWhile_flat")
public func kk_string_dropWhile_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_dropWhile(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

// MARK: - onEach (STDLIB-TEXT-FN-039)

@_cdecl("kk_string_onEach")
public func kk_string_onEach(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return strRaw }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for scalar in scalars {
        var thrown = 0
        _ = lambda(closureRaw, Int(scalar.value), &thrown)
        if thrown != 0 { outThrown?.pointee = thrown; return strRaw }
    }
    return strRaw
}

@_cdecl("kk_string_onEach_flat")
public func kk_string_onEach_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_onEach(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_string_splitToSequence")
public func kk_string_splitToSequence(_ strRaw: Int, _ delimRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let delimiter = runtimeStringFromRawOrPanic(delimRaw, caller: #function)

    if delimiter.isEmpty {
        let singleElement = runtimeMakeStringRaw(source)
        let seq = RuntimeSequenceBox(steps: [.source(elements: [singleElement])])
        return registerRuntimeObject(seq)
    }

    let splitStrings = runtimeSplitString(source, delimiter: delimiter).map { runtimeMakeStringRaw($0) }
    let seq = RuntimeSequenceBox(steps: [.source(elements: splitStrings)])
    return registerRuntimeObject(seq)
}

@_cdecl("__kk_string_splitToSequence")
public func __kk_string_splitToSequence(_ strRaw: Int, _ delimRaw: Int) -> Int {
    kk_string_splitToSequence(strRaw, delimRaw)
}

@_cdecl("kk_string_splitToSequence_flat")
public func kk_string_splitToSequence_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ delimData: UnsafePointer<UInt8>?,
    _ delimLength: Int,
    _ delimByteCount: Int,
    _ delimHash: Int
) -> Int {
    kk_string_splitToSequence(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(delimData, delimLength, delimByteCount, delimHash)
    )
}

@_cdecl("kk_string_joinToString")
public func kk_string_joinToString(
    _ strListRaw: Int, _ separatorRaw: Int, _ prefixRaw: Int, _ postfixRaw: Int
) -> Int {
    guard let list = runtimeListBox(from: strListRaw) else {
        return runtimeMakeStringRaw("")
    }

    let separator = extractString(from: UnsafeMutableRawPointer(bitPattern: separatorRaw)) ?? ", "
    let prefix = extractString(from: UnsafeMutableRawPointer(bitPattern: prefixRaw)) ?? ""
    let postfix = extractString(from: UnsafeMutableRawPointer(bitPattern: postfixRaw)) ?? ""

    let strings = list.values.compactMap { value -> String? in
        switch value.tag {
        case RuntimeValue.stringTag, RuntimeValue.charTag:
            return runtimeElementToString(value)
        default:
            return extractString(from: UnsafeMutableRawPointer(bitPattern: value.legacyRawValue))
        }
    }
    let result = prefix + strings.joined(separator: separator) + postfix
    return runtimeMakeStringRaw(result)
}

@_cdecl("__kk_string_joinToString")
public func __kk_string_joinToString(
    _ strListRaw: Int, _ separatorRaw: Int, _ prefixRaw: Int, _ postfixRaw: Int
) -> Int {
    kk_string_joinToString(strListRaw, separatorRaw, prefixRaw, postfixRaw)
}

@_cdecl("kk_string_find")
public func kk_string_find(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return runtimeNullSentinelInt }
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeNullSentinelInt }
        if result != 0 { return kk_box_char(Int(scalar.value)) }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_string_findLast")
public func kk_string_findLast(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return runtimeNullSentinelInt }
    var foundChar: UnicodeScalar?
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return runtimeNullSentinelInt }
        if result != 0 { foundChar = scalar }
    }
    if let char = foundChar {
        return kk_box_char(Int(char.value))
    }
    return runtimeNullSentinelInt
}

// MARK: - STDLIB-partition: String.partition(predicate)

@_cdecl("kk_string_partition")
public func kk_string_partition(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else {
        return runtimePairNew(
            firstValue: runtimeStringHOFStringValue(runtimeStringFromRawOrPanic(strRaw, caller: #function)),
            secondValue: runtimeStringHOFStringValue("")
        )
    }
    var matched: [UnicodeScalar] = []
    var unmatched: [UnicodeScalar] = []
    for scalar in scalars {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            return runtimePairNew(
                firstValue: runtimeStringHOFStringValue(""),
                secondValue: runtimeStringHOFStringValue("")
            )
        }
        if maybeUnbox(result) != 0 {
            matched.append(scalar)
        } else {
            unmatched.append(scalar)
        }
    }
    return runtimePairNew(
        firstValue: runtimeStringHOFStringValue(runtimeStringFromScalars(matched)),
        secondValue: runtimeStringHOFStringValue(runtimeStringFromScalars(unmatched))
    )
}

@_cdecl("kk_string_partition_flat")
public func kk_string_partition_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_partition(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}

// MARK: - STDLIB-TEXT-FN-040: CharSequence.onEachIndexed
@_cdecl("kk_string_onEachIndexed")
public func kk_string_onEachIndexed(
    _ strRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard fnPtr != 0 else { return strRaw }
    for (index, scalar) in scalars.enumerated() {
        var thrown = 0
        _ = runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: index,
            rhs: Int(scalar.value),
            outThrown: &thrown
        )
        if thrown != 0 { outThrown?.pointee = thrown; return strRaw }
    }
    return strRaw
}

@_cdecl("kk_string_onEachIndexed_flat")
public func kk_string_onEachIndexed_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_string_onEachIndexed(kk_string_from_flat(data, length, byteCount, hash), fnPtr, closureRaw, outThrown)
}
