import Foundation

private struct RuntimeMutableSetFrame {
    var insertionOrder: [Int] = []
}

private struct RuntimeMutableMapFrame {
    var keys: [Int] = []
    var values: [Int] = []
}

private struct RuntimeBuilderThreadState {
    var setFrames: [RuntimeMutableSetFrame] = []
    var mapFrames: [RuntimeMutableMapFrame] = []

    var isEmpty: Bool {
        setFrames.isEmpty && mapFrames.isEmpty
    }
}

private final class RuntimeBuilderState: @unchecked Sendable {
    private let lock = NSLock()
    private var threads: [ObjectIdentifier: RuntimeBuilderThreadState] = [:]
    private let maxDepth = 16

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

@_cdecl("__kk_build_list")
public func __kk_build_list(_ fnRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard fnRaw != 0 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_build_list called with null function pointer")
    }
    let listPtr = kk_list_of(0, 0)
    var thrown = 0
    _ = kk_function_invoke(fnRaw, listPtr, &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
    }
    return listPtr
}

@_cdecl("__kk_build_list_with_capacity")
public func __kk_build_list_with_capacity(
    _ capacity: Int,
    _ fnRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    if capacity < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "capacity must be non-negative.")
        return 0
    }
    return __kk_build_list(fnRaw, outThrown)
}

@_cdecl("__kk_build_set")
public func __kk_build_set(_ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard fnPtr != 0 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_build_set called with null function pointer")
    }
    guard runtimeBuilderState.pushSetFrame() else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_build_set nesting depth exceeded (max 16)")
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

@_cdecl("__kk_build_map")
public func __kk_build_map(_ fnPtr: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard fnPtr != 0 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_build_map called with null function pointer")
    }
    guard runtimeBuilderState.pushMapFrame() else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_build_map nesting depth exceeded (max 16)")
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
