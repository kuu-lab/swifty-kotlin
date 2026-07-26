import Foundation

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
    var listFrames: [RuntimeMutableListFrame] = []
    var setFrames: [RuntimeMutableSetFrame] = []
    var mapFrames: [RuntimeMutableMapFrame] = []

    var isEmpty: Bool {
        listFrames.isEmpty && setFrames.isEmpty && mapFrames.isEmpty
    }
}

private final class RuntimeBuilderState: @unchecked Sendable {
    private let lock = NSLock()
    private var threads: [ObjectIdentifier: RuntimeBuilderThreadState] = [:]
    private let maxDepth = 16

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
