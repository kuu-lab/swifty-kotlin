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

func runtimeResultRunCatching(
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var thrown = 0
    let result = lambda(closureRaw, &thrown)
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

@_cdecl("kk_runtime_result_value_or_null")
public func kk_runtime_result_value_or_null(_ resultRaw: Int) -> Int {
    runtimeResultValueOrNull(resultRaw)
}

@_cdecl("kk_runtime_result_exception_or_null")
public func kk_runtime_result_exception_or_null(_ resultRaw: Int) -> Int {
    runtimeResultExceptionOrNull(resultRaw)
}
