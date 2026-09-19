// KSP-612 / KUU-642: kotlin.DeepRecursiveFunction / DeepRecursiveScope are
// Kotlin source (Sources/CompilerCore/Stdlib/kotlin/DeepRecursive.kt).
//
// The block is a suspend lambda. `callRecursive` is a suspend point that
// records the caller continuation and returns COROUTINE_SUSPENDED; invoke
// runs a heap trampoline loop that starts a fresh coroutine for each
// recursive step and resumes the parked continuation with the result.
// That keeps native stack usage O(1) in the recursion depth, matching
// kotlin-stdlib's DeepRecursiveScopeImpl.runCallLoop.

import Foundation

final class RuntimeDeepRecursiveFunctionBox {
    /// CPS launcher thunk: `(continuation, outThrown) -> Int`.
    let fnPtr: Int
    /// Lowered state-machine symbol id, used as `kk_coroutine_continuation_new` functionID.
    let functionID: Int
    let closureRaw: Int
    /// Number of launcher-arg slots the thunk reads. The last two are always
    /// (scope, value); any prefix slots receive `closureRaw`.
    let launcherArgCount: Int

    init(fnPtr: Int, functionID: Int, closureRaw: Int, launcherArgCount: Int) {
        self.fnPtr = fnPtr
        self.functionID = functionID
        self.closureRaw = closureRaw
        self.launcherArgCount = launcherArgCount
    }
}

/// Sentinel `cont` meaning "resume the cross-function restore trampoline".
private let deepRecursiveCrossFunctionSentinel = -1

final class RuntimeDeepRecursiveScopeBox {
    let function: RuntimeDeepRecursiveFunctionBox
    var currentFunction: RuntimeDeepRecursiveFunctionBox
    var value: Int = 0
    /// Completion for the invocation about to start. `0` is the root `invoke`
    /// caller; `deepRecursiveCrossFunctionSentinel` restores the previous
    /// function before resuming the parked continuation.
    var cont: Int = 0

    var crossFunctionStack: [(restore: RuntimeDeepRecursiveFunctionBox, originalCont: Int)] = []
    var parentOf: [Int: Int] = [:]
    var entryPointOf: [Int: Int] = [:]

    init(function: RuntimeDeepRecursiveFunctionBox) {
        self.function = function
        self.currentFunction = function
    }
}

private enum RuntimeDeepRecursiveTaskScopes {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var scopeByTask: [RuntimeTaskKey: RuntimeDeepRecursiveScopeBox] = [:]

    static func bind(_ scope: RuntimeDeepRecursiveScopeBox, forTask key: RuntimeTaskKey) {
        lock.lock()
        scopeByTask[key] = scope
        lock.unlock()
    }

    static func unbind(forTask key: RuntimeTaskKey) {
        lock.lock()
        scopeByTask.removeValue(forKey: key)
        lock.unlock()
    }

    static var current: RuntimeDeepRecursiveScopeBox? {
        lock.lock()
        defer { lock.unlock() }
        return scopeByTask[RuntimeCoroutineScopeTaskKey.currentTaskKey]
    }
}

private func runtimeDeepRecursiveFunctionBox(from rawValue: Int) -> RuntimeDeepRecursiveFunctionBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeDeepRecursiveFunctionBox.self)
}

private func runtimeDeepRecursiveScopeBox(from rawValue: Int) -> RuntimeDeepRecursiveScopeBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeDeepRecursiveScopeBox.self)
}

private enum DeepRecursiveWork {
    case startNew
    case resume(cont: Int, value: Int, thrown: Int)
}

private func runtimeCallDeepRecursiveEntry(
    entryPointRaw: Int,
    continuation: Int,
    taskKey: RuntimeTaskKey
) -> (result: Int, thrown: Int) {
    guard let entryPoint = suspendEntryPoint(from: entryPointRaw) else {
        return (0, 0)
    }
    guard let state = runtimeContinuationState(from: continuation) else {
        return (0, 0)
    }
    RuntimeContinuationState.installState(state, forTask: taskKey)
    defer { RuntimeContinuationState.removeCurrent(forTask: taskKey) }
    var thrown = 0
    let result = entryPoint(continuation, &thrown)
    return (result, thrown)
}

private func runtimeConfigureDeepRecursiveLauncherArgs(
    continuation: Int,
    function: RuntimeDeepRecursiveFunctionBox,
    scopeRaw: Int,
    value: Int
) {
    let count = max(function.launcherArgCount, 2)
    for slot in 0..<(count - 2) {
        _ = kk_coroutine_launcher_arg_set(continuation, Int64(slot), Int64(function.closureRaw))
    }
    _ = kk_coroutine_launcher_arg_set(continuation, Int64(count - 2), Int64(scopeRaw))
    _ = kk_coroutine_launcher_arg_set(continuation, Int64(count - 1), Int64(value))
}

private func runtimeDeepRecursiveWork(
    after step: (result: Int, thrown: Int),
    resumeCont: Int,
    suspendedToken: Int
) -> DeepRecursiveWork {
    if step.thrown != 0 {
        return .resume(cont: resumeCont, value: 0, thrown: step.thrown)
    }
    if step.result == suspendedToken {
        return .startNew
    }
    return .resume(cont: resumeCont, value: step.result, thrown: 0)
}

private func runtimeCompleteDeepRecursiveInvoke(
    result: Int,
    thrown: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if thrown != 0 {
        runtimeSetThrown(outThrown, thrown)
        return 0
    }
    runtimeSetThrown(outThrown, 0)
    return result
}

private func runtimeInvokeDeepRecursiveOrPanic(
    _ function: RuntimeDeepRecursiveFunctionBox,
    _ value: Int
) -> Int {
    var thrown = 0
    let result = runtimeInvokeDeepRecursive(function, value, &thrown)
    if thrown != 0 {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: DeepRecursiveFunction block threw")
    }
    return result
}

private func runtimeInvokeDeepRecursive(
    _ function: RuntimeDeepRecursiveFunctionBox,
    _ value: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if function.functionID == 0 {
        return runtimeInvokeDeepRecursiveLegacy(function, value, outThrown)
    }

    let scope = RuntimeDeepRecursiveScopeBox(function: function)
    scope.value = value
    let scopeRaw = registerRuntimeObject(scope)

    let taskKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
    RuntimeDeepRecursiveTaskScopes.bind(scope, forTask: taskKey)
    defer {
        RuntimeDeepRecursiveTaskScopes.unbind(forTask: taskKey)
        RuntimeCoroutineScopeTaskKey.removeKey()
    }

    let (finalResult, finalThrown) = runtimeRunDeepRecursiveTrampoline(
        scope: scope,
        scopeRaw: scopeRaw,
        taskKey: taskKey
    )
    return runtimeCompleteDeepRecursiveInvoke(result: finalResult, thrown: finalThrown, outThrown: outThrown)
}

private func runtimeRunDeepRecursiveTrampoline(
    scope: RuntimeDeepRecursiveScopeBox,
    scopeRaw: Int,
    taskKey: RuntimeTaskKey
) -> (result: Int, thrown: Int) {
    let suspendedToken = Int(bitPattern: kk_coroutine_suspended())
    var work = DeepRecursiveWork.startNew
    while true {
        switch work {
        case .startNew:
            let active = scope.currentFunction
            let child = kk_coroutine_continuation_new(active.functionID)
            runtimeConfigureDeepRecursiveLauncherArgs(
                continuation: child,
                function: active,
                scopeRaw: scopeRaw,
                value: scope.value
            )
            scope.parentOf[child] = scope.cont
            scope.entryPointOf[child] = active.fnPtr
            work = runtimeDeepRecursiveWork(
                after: runtimeCallDeepRecursiveEntry(
                    entryPointRaw: active.fnPtr,
                    continuation: child,
                    taskKey: taskKey
                ),
                resumeCont: scope.cont,
                suspendedToken: suspendedToken
            )

        case let .resume(cont, value, thrown):
            switch cont {
            case 0:
                return (value, thrown)
            case deepRecursiveCrossFunctionSentinel:
                guard let frame = scope.crossFunctionStack.popLast() else {
                    return (value, thrown)
                }
                scope.currentFunction = frame.restore
                work = .resume(cont: frame.originalCont, value: value, thrown: thrown)
            default:
                guard let state = runtimeContinuationState(from: cont),
                      let entryPointRaw = scope.entryPointOf[cont]
                else {
                    return (0, thrown)
                }
                state.completion = Int64(value)
                state.thrownException = thrown
                state.resetResumeState()
                work = runtimeDeepRecursiveWork(
                    after: runtimeCallDeepRecursiveEntry(
                        entryPointRaw: entryPointRaw,
                        continuation: cont,
                        taskKey: taskKey
                    ),
                    resumeCont: scope.parentOf[cont] ?? 0,
                    suspendedToken: suspendedToken
                )
            }
        }
    }
}

/// Fallback used when the constructor was not rewritten to a CPS entry point.
/// Still propagates block exceptions through `outThrown` instead of fatalError.
private func runtimeInvokeDeepRecursiveLegacy(
    _ function: RuntimeDeepRecursiveFunctionBox,
    _ value: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let scopeRaw = registerRuntimeObject(RuntimeDeepRecursiveScopeBox(function: function))
    var thrown = 0
    let result: Int
    if function.closureRaw != 0 {
        let fn = unsafeBitCast(function.fnPtr, to: KKClosureFunctionEntryPoint2.self)
        result = fn(function.closureRaw, scopeRaw, value, &thrown)
    } else {
        let fn = unsafeBitCast(function.fnPtr, to: KKFunctionEntryPoint2.self)
        result = fn(scopeRaw, value, &thrown)
    }
    return runtimeCompleteDeepRecursiveInvoke(result: result, thrown: thrown, outThrown: outThrown)
}

private func runtimeParkDeepRecursiveCall(
    scope: RuntimeDeepRecursiveScopeBox,
    value: Int,
    continuation: Int,
    nextFunction: RuntimeDeepRecursiveFunctionBox
) -> Int {
    if nextFunction !== scope.currentFunction {
        scope.crossFunctionStack.append((restore: scope.currentFunction, originalCont: continuation))
        scope.currentFunction = nextFunction
        scope.cont = deepRecursiveCrossFunctionSentinel
    } else {
        scope.cont = continuation
    }
    scope.value = value
    return Int(bitPattern: kk_coroutine_suspended())
}

@_cdecl("__kk_deep_recursive_function_new")
public func kk_deep_recursive_bridge_function_new(
    _ fnPtr: Int,
    _ functionID: Int,
    _ closureRaw: Int,
    _ launcherArgCount: Int
) -> Int {
    guard fnPtr != 0 else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: DeepRecursiveFunction requires a valid block")
    }
    return registerRuntimeObject(
        RuntimeDeepRecursiveFunctionBox(
            fnPtr: fnPtr,
            functionID: functionID,
            closureRaw: closureRaw,
            launcherArgCount: launcherArgCount
        )
    )
}

@_cdecl("__kk_deep_recursive_function_invoke")
public func kk_deep_recursive_bridge_function_invoke(
    _ functionRaw: Int,
    _ value: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let function = runtimeDeepRecursiveFunctionBox(from: functionRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid DeepRecursiveFunction handle")
    }
    return runtimeInvokeDeepRecursive(function, value, outThrown)
}

@_cdecl("__kk_deep_recursive_scope_callRecursive")
public func kk_deep_recursive_bridge_scope_callRecursive(
    _ scopeRaw: Int,
    _ value: Int,
    _ continuation: Int
) -> Int {
    guard let scope = runtimeDeepRecursiveScopeBox(from: scopeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid DeepRecursiveScope handle")
    }
    guard continuation != 0 else {
        return runtimeInvokeDeepRecursiveOrPanic(scope.currentFunction, value)
    }
    return runtimeParkDeepRecursiveCall(
        scope: scope,
        value: value,
        continuation: continuation,
        nextFunction: scope.currentFunction
    )
}

@_cdecl("__kk_deep_recursive_function_callRecursive")
public func kk_deep_recursive_bridge_function_callRecursive(
    _ functionRaw: Int,
    _ value: Int,
    _ continuation: Int
) -> Int {
    guard let function = runtimeDeepRecursiveFunctionBox(from: functionRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid DeepRecursiveFunction handle")
    }
    guard continuation != 0, let scope = RuntimeDeepRecursiveTaskScopes.current else {
        return runtimeInvokeDeepRecursiveOrPanic(function, value)
    }
    return runtimeParkDeepRecursiveCall(
        scope: scope,
        value: value,
        continuation: continuation,
        nextFunction: function
    )
}
