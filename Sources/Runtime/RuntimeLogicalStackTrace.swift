import Foundation

struct RuntimeLogicalStackTraceFrame: Equatable, Sendable {
    // Generated code passes pointers to compiler-emitted static C strings, so
    // the names stay as raw addresses and are decoded only when a trace is
    // materialized (exception paths).  Every Kotlin call enters and exits a
    // frame; allocating three Strings per call dominated profile time.
    var classNameRaw: Int
    var methodNameRaw: Int
    var fileNameRaw: Int
    var line: Int

    var className: String { runtimeStackTraceCString(classNameRaw) }
    var methodName: String { runtimeStackTraceCString(methodNameRaw) }
    var fileName: String { runtimeStackTraceCString(fileNameRaw) }
}

private final class RuntimeLogicalStackTraceState {
    var frames: [RuntimeLogicalStackTraceFrame] = []
}

private let runtimeLogicalStackTraceTLSKey = makePthreadKey()

private func runtimeLogicalStackTraceState(createIfNeeded: Bool) -> RuntimeLogicalStackTraceState? {
    if let state: RuntimeLogicalStackTraceState = pthreadGetValue(runtimeLogicalStackTraceTLSKey) {
        return state
    }
    guard createIfNeeded else { return nil }
    let state = RuntimeLogicalStackTraceState()
    pthreadSetValue(runtimeLogicalStackTraceTLSKey, state)
    return state
}

private func runtimeStackTraceCString(_ address: Int) -> String {
    guard let pointer = UnsafePointer<CChar>(bitPattern: UInt(bitPattern: address)) else {
        return ""
    }
    return String(cString: pointer)
}

@_cdecl("kk_runtime_stack_trace_enter")
public func kk_runtime_stack_trace_enter(
    _ classNameRaw: Int,
    _ methodNameRaw: Int,
    _ fileNameRaw: Int,
    _ line: Int
) -> Int {
    guard let state = runtimeLogicalStackTraceState(createIfNeeded: true) else { return 0 }
    state.frames.append(RuntimeLogicalStackTraceFrame(
        classNameRaw: classNameRaw,
        methodNameRaw: methodNameRaw,
        fileNameRaw: fileNameRaw,
        line: max(0, line)
    ))
    return 0
}

@_cdecl("kk_runtime_stack_trace_set_location")
public func kk_runtime_stack_trace_set_location(_ fileNameRaw: Int, _ line: Int) -> Int {
    guard let state = runtimeLogicalStackTraceState(createIfNeeded: false),
          let frameIndex = state.frames.indices.last
    else {
        return 0
    }
    state.frames[frameIndex].fileNameRaw = fileNameRaw
    state.frames[frameIndex].line = max(0, line)
    return 0
}

@_cdecl("kk_runtime_stack_trace_exit")
public func kk_runtime_stack_trace_exit() -> Int {
    _ = runtimeLogicalStackTraceState(createIfNeeded: false)?.frames.popLast()
    return 0
}

func runtimeCurrentLogicalStackTrace() -> [RuntimeLogicalStackTraceFrame] {
    guard let frames = runtimeLogicalStackTraceState(createIfNeeded: false)?.frames else {
        return []
    }
    let innermostFirst = frames.reversed()
    return Array(innermostFirst.drop(while: { $0.methodName == "<init>" }))
}

func runtimeThrowableStackTraceLines(_ frames: [RuntimeLogicalStackTraceFrame]) -> [String] {
    frames.map { frame in
        let location: String
        if frame.fileName.isEmpty || frame.fileName == "Unknown Source" {
            location = "Unknown Source"
        } else if frame.line > 0 {
            location = "\(frame.fileName):\(frame.line)"
        } else {
            location = frame.fileName
        }
        return "\tat \(frame.className).\(frame.methodName)(\(location))"
    }
}
