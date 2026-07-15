import Foundation

private struct RuntimeStringBuilderFrame {
    var value = ""
}

private struct RuntimeMutableListFrame {
    var elements: [Int] = []
}

private struct RuntimeMutableSetFrame {
    var elements: Set<RuntimeElementKey> = []
    var insertionOrder: [Int] = []
}

private struct RuntimeMutableMapFrame {
    var keys: [Int] = []
    var values: [Int] = []
}

private struct RuntimeBuilderThreadState {
    var stringFrames: [RuntimeStringBuilderFrame] = []
    var listFrames: [RuntimeMutableListFrame] = []
    var setFrames: [RuntimeMutableSetFrame] = []
    var mapFrames: [RuntimeMutableMapFrame] = []

    var isEmpty: Bool {
        stringFrames.isEmpty && listFrames.isEmpty && setFrames.isEmpty && mapFrames.isEmpty
    }
}

private final class RuntimeBuilderState: @unchecked Sendable {
    private let lock = NSLock()
    private var threads: [ObjectIdentifier: RuntimeBuilderThreadState] = [:]
    private let maxDepth = 16

    func pushStringFrame() -> Bool {
        withThreadState { state in
            guard state.stringFrames.count < maxDepth else {
                return false
            }
            state.stringFrames.append(RuntimeStringBuilderFrame())
            return true
        }
    }

    func popStringFrame() -> RuntimeStringBuilderFrame? {
        withThreadState { state in
            state.stringFrames.popLast()
        }
    }

    func appendString(_ value: String) {
        withThreadState { state in
            guard !state.stringFrames.isEmpty else {
                return
            }
            state.stringFrames[state.stringFrames.count - 1].value.append(value)
        }
    }

    func insertString(_ value: String, at index: Int) {
        withThreadState { state in
            guard !state.stringFrames.isEmpty else {
                return
            }
            let frameIndex = state.stringFrames.count - 1
            let str = state.stringFrames[frameIndex].value
            let utf8 = str.utf8
            let clampedIndex = max(0, min(index, utf8.count))
            let insertionPoint = utf8.index(utf8.startIndex, offsetBy: clampedIndex)
            state.stringFrames[frameIndex].value.insert(contentsOf: value, at: insertionPoint)
        }
    }

    func deleteString(start: Int, end: Int) {
        withThreadState { state in
            guard !state.stringFrames.isEmpty else {
                return
            }
            let frameIndex = state.stringFrames.count - 1
            let str = state.stringFrames[frameIndex].value
            let utf8 = str.utf8
            let clampedStart = max(0, min(start, utf8.count))
            let clampedEnd = max(clampedStart, min(end, utf8.count))
            let startIdx = utf8.index(utf8.startIndex, offsetBy: clampedStart)
            let endIdx = utf8.index(utf8.startIndex, offsetBy: clampedEnd)
            state.stringFrames[frameIndex].value.removeSubrange(startIdx..<endIdx)
        }
    }

    func stringLength() -> Int {
        withThreadState { state in
            guard !state.stringFrames.isEmpty else {
                return 0
            }
            return state.stringFrames[state.stringFrames.count - 1].value.utf8.count
        }
    }

    func pushListFrame() -> Bool {
        withThreadState { state in
            guard state.listFrames.count < maxDepth else {
                return false
            }
            state.listFrames.append(RuntimeMutableListFrame())
            return true
        }
    }

    func popListFrame() -> RuntimeMutableListFrame? {
        withThreadState { state in
            state.listFrames.popLast()
        }
    }

    func appendListElement(_ value: Int) {
        withThreadState { state in
            guard !state.listFrames.isEmpty else {
                return
            }
            state.listFrames[state.listFrames.count - 1].elements.append(value)
        }
    }

    func appendListElements(_ values: [Int]) {
        withThreadState { state in
            guard !state.listFrames.isEmpty else {
                return
            }
            state.listFrames[state.listFrames.count - 1].elements.append(contentsOf: values)
        }
    }

    func pushSetFrame() -> Bool {
        withThreadState { state in
            guard state.setFrames.count < maxDepth else {
                return false
            }
            state.setFrames.append(RuntimeMutableSetFrame())
            return true
        }
    }

    func popSetFrame() -> RuntimeMutableSetFrame? {
        withThreadState { state in
            state.setFrames.popLast()
        }
    }

    func addSetElement(_ value: Int) {
        withThreadState { state in
            guard !state.setFrames.isEmpty else {
                return
            }
            let index = state.setFrames.count - 1
            let key = RuntimeElementKey(value: value)
            if state.setFrames[index].elements.insert(key).inserted {
                state.setFrames[index].insertionOrder.append(value)
            }
        }
    }

    func addSetElements(_ values: [Int]) {
        withThreadState { state in
            guard !state.setFrames.isEmpty else {
                return
            }
            let index = state.setFrames.count - 1
            for value in values {
                let key = RuntimeElementKey(value: value)
                if state.setFrames[index].elements.insert(key).inserted {
                    state.setFrames[index].insertionOrder.append(value)
                }
            }
        }
    }

    func pushMapFrame() -> Bool {
        withThreadState { state in
            guard state.mapFrames.count < maxDepth else {
                return false
            }
            state.mapFrames.append(RuntimeMutableMapFrame())
            return true
        }
    }

    func popMapFrame() -> RuntimeMutableMapFrame? {
        withThreadState { state in
            state.mapFrames.popLast()
        }
    }

    func putMapEntry(key: Int, value: Int) {
        withThreadState { state in
            guard !state.mapFrames.isEmpty else {
                return
            }
            let index = state.mapFrames.count - 1
            if let existing = state.mapFrames[index].keys.firstIndex(of: key) {
                state.mapFrames[index].values[existing] = value
                return
            }
            state.mapFrames[index].keys.append(key)
            state.mapFrames[index].values.append(value)
        }
    }

    private func withThreadState<R>(_ body: (inout RuntimeBuilderThreadState) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        let threadID = ObjectIdentifier(Thread.current)
        var state = threads[threadID] ?? RuntimeBuilderThreadState()
        let result = body(&state)
        if state.isEmpty {
            threads.removeValue(forKey: threadID)
        } else {
            threads[threadID] = state
        }
        return result
    }
}

private let runtimeBuilderState = RuntimeBuilderState()

@_cdecl("kk_string_builder_append_flat")
public func kk_string_builder_append_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeBuildStringAppend(
        runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}

private func runtimeBuildStringAppend(_ string: String) -> Int {
    runtimeBuilderState.appendString(string)
    return 0
}

@_cdecl("kk_string_builder_append_line_flat")
public func kk_string_builder_append_line_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeBuildStringAppendLine(
        runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}

private func runtimeBuildStringAppendLine(_ string: String) -> Int {
    runtimeBuilderState.appendString(string)
    runtimeBuilderState.appendString("\n")
    return 0
}

@_cdecl("kk_string_builder_append")
public func kk_string_builder_append(_ valueRaw: Int) -> Int {
    runtimeBuilderState.appendString(runtimeElementToString(valueRaw))
    return 0
}

@_cdecl("kk_string_builder_append_line")
public func kk_string_builder_append_line(_ valueRaw: Int) -> Int {
    runtimeBuilderState.appendString(runtimeElementToString(valueRaw))
    runtimeBuilderState.appendString("\n")
    return 0
}

@_cdecl("kk_string_builder_append_line_noarg")
public func kk_string_builder_append_line_noarg() -> Int {
    runtimeBuilderState.appendString("\n")
    return 0
}

@_cdecl("kk_string_builder_append_range_flat")
public func kk_string_builder_append_range_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ startIndex: Int,
    _ endIndex: Int
) -> Int {
    runtimeBuildStringAppendRange(
        runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash),
        startIndex: startIndex,
        endIndex: endIndex
    )
}

private func runtimeBuildStringAppendRange(_ string: String, startIndex: Int, endIndex: Int) -> Int {
    runtimeBuilderState.appendString(runtimeUTF16Substring(string, startIndex: startIndex, endIndex: endIndex))
    return 0
}

@_cdecl("kk_string_builder_insert_flat")
public func kk_string_builder_insert_flat(
    _ index: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    runtimeBuildStringInsert(
        index: index,
        value: runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    )
}

private func runtimeBuildStringInsert(index: Int, value string: String) -> Int {
    runtimeBuilderState.insertString(string, at: index)
    return 0
}

@_cdecl("kk_string_builder_delete")
public func kk_string_builder_delete(_ start: Int, _ end: Int) -> Int {
    runtimeBuilderState.deleteString(start: start, end: end)
    return 0
}

@_cdecl("kk_string_builder_length")
public func kk_string_builder_length() -> Int {
    return runtimeBuilderState.stringLength()
}

private func runtimeExecuteStringBuilderAction(
    _ fnPtr: Int,
    _ outThrown: UnsafeMutablePointer<Int>?,
    functionName: String
) -> RuntimeStringBuilderFrame {
    outThrown?.pointee = 0
    guard fnPtr != 0 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(functionName) called with null function pointer")
    }
    guard runtimeBuilderState.pushStringFrame() else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(functionName) nesting depth exceeded (max 16)")
    }

    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    _ = lambda(&thrown)

    if thrown != 0 {
        outThrown?.pointee = thrown
    }

    return runtimeBuilderState.popStringFrame() ?? RuntimeStringBuilderFrame()
}

@_cdecl("kk_build_string")
public func kk_build_string(_ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let frame = runtimeExecuteStringBuilderAction(fnPtr, outThrown, functionName: "kk_build_string")
    return runtimeMakeStringRaw(frame.value)
}

@_cdecl("kk_build_string_with_capacity")
public func kk_build_string_with_capacity(
    _ capacity: Int,
    _ fnPtr: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    // capacity is an optimization hint only; no semantic difference from kk_build_string.
    if capacity < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "capacity must be non-negative.")
        return 0
    }
    return kk_build_string(fnPtr, outThrown)
}

@_cdecl("kk_build_string_builder")
public func kk_build_string_builder(_ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let frame = runtimeExecuteStringBuilderAction(fnPtr, outThrown, functionName: "kk_build_string_builder")
    return registerRuntimeObject(RuntimeStringBuilderBox(frame.value))
}

@_cdecl("kk_build_string_builder_with_capacity")
public func kk_build_string_builder_with_capacity(
    _ capacity: Int,
    _ fnPtr: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if capacity < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "capacity must be non-negative.")
        return 0
    }
    return kk_build_string_builder(fnPtr, outThrown)
}

@_cdecl("kk_builder_list_add")
public func kk_builder_list_add(_ elem: Int) -> Int {
    runtimeBuilderState.appendListElement(elem)
    return 0
}

@_cdecl("kk_builder_list_addAll")
public func kk_builder_list_addAll(_ collectionRaw: Int) -> Int {
    var elements: [Int] = []
    if let listBox = runtimeListBox(from: collectionRaw) {
        elements = listBox.elements
    } else if let setBox = runtimeSetBox(from: collectionRaw) {
        elements = setBox.elements
    }
    runtimeBuilderState.appendListElements(elements)
    return 0
}

@_cdecl("kk_build_list")
public func kk_build_list(_ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard fnPtr != 0 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_build_list called with null function pointer")
    }
    guard runtimeBuilderState.pushListFrame() else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_build_list nesting depth exceeded (max 16)")
    }

    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    _ = lambda(&thrown)

    if thrown != 0 {
        outThrown?.pointee = thrown
    }

    let frame = runtimeBuilderState.popListFrame() ?? RuntimeMutableListFrame()
    return registerRuntimeObject(RuntimeListBox(elements: frame.elements))
}

@_cdecl("kk_build_list_with_capacity")
public func kk_build_list_with_capacity(
    _ capacity: Int,
    _ fnPtr: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    if capacity < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "capacity must be non-negative.")
        return 0
    }
    return kk_build_list(fnPtr, outThrown)
}

@_cdecl("kk_builder_set_add")
public func kk_builder_set_add(_ elem: Int) -> Int {
    runtimeBuilderState.addSetElement(elem)
    return 0
}

@_cdecl("kk_builder_set_addAll")
public func kk_builder_set_addAll(_ collectionRaw: Int) -> Int {
    var elements: [Int] = []
    if let listBox = runtimeListBox(from: collectionRaw) {
        elements = listBox.elements
    } else if let setBox = runtimeSetBox(from: collectionRaw) {
        elements = setBox.elements
    }
    runtimeBuilderState.addSetElements(elements)
    return 0
}

@_cdecl("kk_build_set")
public func kk_build_set(_ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard fnPtr != 0 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_build_set called with null function pointer")
    }
    guard runtimeBuilderState.pushSetFrame() else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_build_set nesting depth exceeded (max 16)")
    }

    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    _ = lambda(&thrown)

    if thrown != 0 {
        outThrown?.pointee = thrown
    }

    let frame = runtimeBuilderState.popSetFrame() ?? RuntimeMutableSetFrame()
    return registerRuntimeObject(RuntimeSetBox(elements: frame.insertionOrder))
}

@_cdecl("kk_builder_map_put")
public func kk_builder_map_put(_ key: Int, _ value: Int) -> Int {
    runtimeBuilderState.putMapEntry(key: key, value: value)
    return 0
}

@_cdecl("kk_build_map")
public func kk_build_map(_ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard fnPtr != 0 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_build_map called with null function pointer")
    }
    guard runtimeBuilderState.pushMapFrame() else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_build_map nesting depth exceeded (max 16)")
    }

    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    _ = lambda(&thrown)

    if thrown != 0 {
        outThrown?.pointee = thrown
    }

    let frame = runtimeBuilderState.popMapFrame() ?? RuntimeMutableMapFrame()
    return registerRuntimeObject(RuntimeMapBox(keys: frame.keys, values: frame.values))
}

