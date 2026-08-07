import Dispatch
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// MARK: - kotlin.system OS bridges (KSP-617)
//
// The public kotlin.system surface lives in bundled Kotlin source
// (Sources/CompilerCore/Stdlib/kotlin/system/). Only the OS entry points stay
// here, demoted to __kk_ so they are reachable from the stdlib layer alone.

@_cdecl("__kk_system_exitProcess")
public func __kk_system_exitProcess(_ status: Int) -> Never {
    exit(Int32(status))
}

/// Not monotonic — reads the system real-time clock, which may jump on NTP adjustments.
@_cdecl("__kk_system_currentTimeMillis")
public func __kk_system_currentTimeMillis() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
}

@_cdecl("__kk_system_getTimeMillis")
public func __kk_system_getTimeMillis() -> Int {
    __kk_system_currentTimeMillis()
}

@_cdecl("__kk_system_nanoTime")
public func __kk_system_nanoTime() -> Int {
    // 64-bit: Int.max ≈ 292 years of ns — clamping is effectively a no-op.
    Int(clamping: DispatchTime.now().uptimeNanoseconds)
}

@_cdecl("__kk_system_getTimeMicros")
public func __kk_system_getTimeMicros() -> Int {
    __kk_system_nanoTime() / 1_000
}

@_cdecl("__kk_system_getTimeNanos")
public func __kk_system_getTimeNanos() -> Int {
    __kk_system_nanoTime()
}

// MARK: - processStartNanos (STDLIB-TIME-085)

private let processStartNanosValue: Int = Int(clamping: DispatchTime.now().uptimeNanoseconds)

@_cdecl("__kk_system_process_start_nanos")
public func __kk_system_process_start_nanos() -> Int {
    processStartNanosValue
}
