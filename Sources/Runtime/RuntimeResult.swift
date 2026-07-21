// MARK: - Result Runtime Types

final class RuntimeResultBox {
    let isSuccess: Bool
    let value: Int      // success value or 0
    let exception: Int  // throwable or 0

    init(isSuccess: Bool, value: Int, exception: Int) {
        self.isSuccess = isSuccess
        self.value = value
        self.exception = exception
    }
}

private func resultBoxFromRaw(_ raw: Int) -> RuntimeResultBox? {
    guard let pointer = normalizeNullableRuntimePointer(UnsafeMutableRawPointer(bitPattern: raw)) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(pointer, to: RuntimeResultBox.self)
}

func runtimeResultSuccess(_ value: Int) -> Int {
    registerRuntimeObject(RuntimeResultBox(isSuccess: true, value: value, exception: 0))
}

func runtimeResultFailure(_ exception: Int) -> Int {
    registerRuntimeObject(RuntimeResultBox(isSuccess: false, value: 0, exception: exception))
}

func runtimeResultIsSuccess(_ resultRaw: Int) -> Bool {
    guard let box = resultBoxFromRaw(resultRaw) else { return false }
    return box.isSuccess
}

func runtimeResultIsFailure(_ resultRaw: Int) -> Bool {
    !runtimeResultIsSuccess(resultRaw)
}

func runtimeResultValueOrNull(_ resultRaw: Int) -> Int {
    guard let box = resultBoxFromRaw(resultRaw), box.isSuccess else {
        return runtimeNullSentinelInt
    }
    return box.value
}

func runtimeResultExceptionOrNull(_ resultRaw: Int) -> Int {
    guard let box = resultBoxFromRaw(resultRaw) else {
        return runtimeNullSentinelInt
    }
    if box.isSuccess {
        return runtimeNullSentinelInt
    }
    return box.exception
}

/// Invokes a Result block as either a boxed function value or a raw closure entrypoint.
private func runtimeResultInvoke0(fnPtr: Int, closureRaw: Int) -> (result: Int, thrown: Int) {
    var thrown = 0
    let result: Int
    if runtimeFunctionValueBox(from: fnPtr) != nil {
        result = kk_function_invoke_0(fnPtr, &thrown)
    } else {
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
        result = lambda(closureRaw, &thrown)
    }
    return (result, thrown)
}

func runtimeResultRunCatching(
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let (result, thrown) = runtimeResultInvoke0(fnPtr: fnPtr, closureRaw: closureRaw)
    if thrown != 0 {
        return runtimeResultFailure(thrown)
    }
    return runtimeResultSuccess(result)
}

func runtimeResultSuccessFlag(_ resultRaw: Int) -> Int {
    runtimeResultIsSuccess(resultRaw) ? 1 : 0
}

func runtimeResultFailureFlag(_ resultRaw: Int) -> Int {
    runtimeResultIsFailure(resultRaw) ? 1 : 0
}

func runtimeResultValueOrDefault(_ resultRaw: Int, _ defaultValue: Int) -> Int {
    let value = runtimeResultValueOrNull(resultRaw)
    return value == runtimeNullSentinelInt ? defaultValue : value
}

func runtimeResultGetOrThrow(
    _ resultRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = resultBoxFromRaw(resultRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Result is null")
        return 0
    }
    if box.isSuccess {
        return box.value
    }
    outThrown?.pointee = box.exception
    return 0
}

private func runtimeResultInvoke1(
    fnPtr: Int,
    closureRaw: Int,
    value: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var thrown = 0
    let result: Int
    if runtimeFunctionValueBox(from: fnPtr) != nil {
        result = kk_function_invoke(fnPtr, value, &thrown)
    } else {
        result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: value,
            outThrown: &thrown
        )
    }
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

func runtimeResultGetOrElse(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = resultBoxFromRaw(resultRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Result is null")
        return 0
    }
    if box.isSuccess {
        return box.value
    }
    return runtimeResultInvoke1(fnPtr: fnPtr, closureRaw: closureRaw, value: box.exception, outThrown: outThrown)
}

func runtimeResultMap(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = resultBoxFromRaw(resultRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Result is null")
        return 0
    }
    if !box.isSuccess {
        return runtimeResultFailure(box.exception)
    }
    var thrown = 0
    let transformed = runtimeResultInvoke1(fnPtr: fnPtr, closureRaw: closureRaw, value: box.value, outThrown: &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return runtimeResultSuccess(transformed)
}

func runtimeResultFold(
    _ resultRaw: Int,
    _ successFnPtr: Int,
    _ successClosureRaw: Int,
    _ failureFnPtr: Int,
    _ failureClosureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = resultBoxFromRaw(resultRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Result is null")
        return 0
    }
    if box.isSuccess {
        return runtimeResultInvoke1(
            fnPtr: successFnPtr,
            closureRaw: successClosureRaw,
            value: box.value,
            outThrown: outThrown
        )
    }
    return runtimeResultInvoke1(
        fnPtr: failureFnPtr,
        closureRaw: failureClosureRaw,
        value: box.exception,
        outThrown: outThrown
    )
}

func runtimeResultOnSuccess(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = resultBoxFromRaw(resultRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Result is null")
        return 0
    }
    if box.isSuccess {
        var thrown = 0
        _ = runtimeResultInvoke1(fnPtr: fnPtr, closureRaw: closureRaw, value: box.value, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
    }
    return resultRaw
}

func runtimeResultOnFailure(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = resultBoxFromRaw(resultRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Result is null")
        return 0
    }
    if !box.isSuccess {
        var thrown = 0
        _ = runtimeResultInvoke1(fnPtr: fnPtr, closureRaw: closureRaw, value: box.exception, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
    }
    return resultRaw
}

func runtimeResultRecover(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = resultBoxFromRaw(resultRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Result is null")
        return 0
    }
    if box.isSuccess {
        return runtimeResultSuccess(box.value)
    }
    var thrown = 0
    let recovered = runtimeResultInvoke1(fnPtr: fnPtr, closureRaw: closureRaw, value: box.exception, outThrown: &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return runtimeResultSuccess(recovered)
}

func runtimeResultRecoverCatching(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let box = resultBoxFromRaw(resultRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Result is null")
        return 0
    }
    if box.isSuccess {
        return runtimeResultSuccess(box.value)
    }
    var thrown = 0
    let recovered = runtimeResultInvoke1(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        value: box.exception,
        outThrown: &thrown
    )
    if thrown != 0 {
        return runtimeResultFailure(thrown)
    }
    return runtimeResultSuccess(recovered)
}

// MARK: - Bundled Result.kt Runtime Bridges

@_cdecl("kk_runtime_result_success")
public func kk_runtime_result_success(_ value: Int) -> Int {
    runtimeResultSuccess(value)
}

@_cdecl("kk_runtime_result_failure")
public func kk_runtime_result_failure(_ exception: Int) -> Int {
    runtimeResultFailure(exception)
}

@_cdecl("kk_runtime_result_is_success")
public func kk_runtime_result_is_success(_ resultRaw: Int) -> Int {
    runtimeResultIsSuccess(resultRaw) ? 1 : 0
}

@_cdecl("kk_runtime_result_is_failure")
public func kk_runtime_result_is_failure(_ resultRaw: Int) -> Int {
    runtimeResultIsFailure(resultRaw) ? 1 : 0
}

@_cdecl("kk_runtime_result_value_or_null")
public func kk_runtime_result_value_or_null(_ resultRaw: Int) -> Int {
    runtimeResultValueOrNull(resultRaw)
}

@_cdecl("kk_runtime_result_get_or_throw")
public func kk_runtime_result_get_or_throw(
    _ resultRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeResultGetOrThrow(resultRaw, outThrown)
}

@_cdecl("kk_runtime_result_exception_or_null")
public func kk_runtime_result_exception_or_null(_ resultRaw: Int) -> Int {
    runtimeResultExceptionOrNull(resultRaw)
}

@_cdecl("kk_runtime_result_run_catching")
public func kk_runtime_result_run_catching(
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeResultRunCatching(fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_runtime_result_get_or_else")
public func kk_runtime_result_get_or_else(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeResultGetOrElse(resultRaw, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_runtime_result_map")
public func kk_runtime_result_map(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeResultMap(resultRaw, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_runtime_result_fold")
public func kk_runtime_result_fold(
    _ resultRaw: Int,
    _ successFnPtr: Int,
    _ successClosureRaw: Int,
    _ failureFnPtr: Int,
    _ failureClosureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeResultFold(resultRaw, successFnPtr, successClosureRaw, failureFnPtr, failureClosureRaw, outThrown)
}

@_cdecl("kk_runtime_result_on_success")
public func kk_runtime_result_on_success(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeResultOnSuccess(resultRaw, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_runtime_result_on_failure")
public func kk_runtime_result_on_failure(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeResultOnFailure(resultRaw, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_runtime_result_recover")
public func kk_runtime_result_recover(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeResultRecover(resultRaw, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_runtime_result_recover_catching")
public func kk_runtime_result_recover_catching(
    _ resultRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeResultRecoverCatching(resultRaw, fnPtr, closureRaw, outThrown)
}
