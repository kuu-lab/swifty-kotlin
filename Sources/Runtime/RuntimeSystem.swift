import Dispatch
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// MARK: - kotlin.system functions (STDLIB-131/132, STDLIB-TIME-085)

@_cdecl("kk_system_exitProcess")
public func kk_system_exitProcess(_ status: Int) -> Never {
    exit(Int32(status))
}

/// Not monotonic — reads the system real-time clock, which may jump on NTP adjustments.
@_cdecl("kk_system_currentTimeMillis")
public func kk_system_currentTimeMillis() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
}

@_cdecl("kk_system_getTimeMillis")
public func kk_system_getTimeMillis() -> Int {
    kk_system_currentTimeMillis()
}

@_cdecl("kk_system_nanoTime")
public func kk_system_nanoTime() -> Int {
    // 64-bit: Int.max ≈ 292 years of ns — clamping is effectively a no-op.
    Int(clamping: DispatchTime.now().uptimeNanoseconds)
}

@_cdecl("kk_system_getTimeMicros")
public func kk_system_getTimeMicros() -> Int {
    kk_system_nanoTime() / 1_000
}

@_cdecl("kk_system_getTimeNanos")
public func kk_system_getTimeNanos() -> Int {
    kk_system_nanoTime()
}

// MARK: - processStartNanos (STDLIB-TIME-085)

private let processStartNanosValue: Int = Int(clamping: DispatchTime.now().uptimeNanoseconds)

@_cdecl("kk_system_process_start_nanos")
public func kk_system_process_start_nanos() -> Int {
    processStartNanosValue
}

// MARK: - measureTimeMillis / measureTimeMicros / measureNanoTime (STDLIB-550)

@_cdecl("kk_system_measureTimeMillis")
public func kk_system_measureTimeMillis(
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let start = kk_system_getTimeMillis()
    _ = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
    if let ot = outThrown, ot.pointee != 0 {
        return 0
    }
    let end = kk_system_getTimeMillis()
    return end - start
}

@_cdecl("kk_system_measureTimeMicros")
public func kk_system_measureTimeMicros(
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let start = DispatchTime.now().uptimeNanoseconds
    _ = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
    if let ot = outThrown, ot.pointee != 0 {
        return 0
    }
    let end = DispatchTime.now().uptimeNanoseconds
    return Int(clamping: (end - start) / 1_000)
}

@_cdecl("kk_system_measureNanoTime")
public func kk_system_measureNanoTime(
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let start = DispatchTime.now().uptimeNanoseconds
    _ = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
    if let ot = outThrown, ot.pointee != 0 {
        return 0
    }
    let end = DispatchTime.now().uptimeNanoseconds
    return Int(clamping: end - start)
}
