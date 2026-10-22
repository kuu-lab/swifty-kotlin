import Dispatch
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

private let runtimeSystemProperties: [String: String] = {
    let processInfo = ProcessInfo.processInfo
    let version = processInfo.operatingSystemVersion
    let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    let kotlinVersion = "\(kotlinTargetVersion.major).\(kotlinTargetVersion.minor).\(kotlinTargetVersion.patch)"
    let littleEndian: Bool = {
        var value: UInt32 = 0x0102_0304
        return withUnsafeBytes(of: &value) { $0.first == 0x04 }
    }()

    return [
        "java.vm.name": "KSwiftK Native Runtime",
        // No JVM is hosted; expose the Kotlin compatibility target version.
        "java.version": kotlinVersion,
        "java.class.path": "",
        "sun.java.command": processInfo.arguments.joined(separator: " "),
        "sun.arch.data.model": String(Int.bitWidth),
        "sun.cpu.endian": littleEndian ? "little" : "big",
        "os.name": runtimeSystemOsName,
        "os.version": osVersion,
        "os.arch": runtimeSystemCpuArchitecture,
        "user.name": NSUserName(),
        "user.home": FileManager.default.homeDirectoryForCurrentUser.path,
        "user.dir": FileManager.default.currentDirectoryPath,
        "java.io.tmpdir": FileManager.default.temporaryDirectory.path,
        "file.separator": runtimeSystemFileSeparator,
        "path.separator": runtimeSystemPathSeparator,
        "line.separator": runtimeSystemLineSeparator,
    ]
}()

private let runtimeSystemOsName: String = {
#if os(macOS)
    "Mac OS X"
#elseif os(iOS)
    "iOS"
#elseif os(tvOS)
    "tvOS"
#elseif os(watchOS)
    "watchOS"
#elseif os(Linux)
    "Linux"
#elseif os(Windows)
    "Windows"
#elseif os(Android)
    "Android"
#elseif os(WASI)
    "WASI"
#else
    "Unknown"
#endif
}()

private let runtimeSystemCpuArchitecture: String = {
#if arch(x86_64)
    "x86_64"
#elseif arch(i386)
    "x86"
#elseif arch(arm64)
    "aarch64"
#elseif arch(arm)
    "arm"
#elseif arch(wasm32)
    "wasm32"
#else
    "unknown"
#endif
}()

private let runtimeSystemFileSeparator: String = {
#if os(Windows)
    "\\"
#else
    "/"
#endif
}()

private let runtimeSystemPathSeparator: String = {
#if os(Windows)
    ";"
#else
    ":"
#endif
}()

private let runtimeSystemLineSeparator: String = {
#if os(Windows)
    "\r\n"
#else
    "\n"
#endif
}()

// The public kotlin.system surface lives in bundled Kotlin source
// (Sources/CompilerCore/Stdlib/kotlin/system/). Only the OS entry points stay
// here, demoted to __kk_ so they are reachable from the stdlib layer alone.

@_cdecl("__kk_system_exitProcess")
public func __kk_system_exitProcess(_ status: Int) -> Never {
    exit(Int32(status))
}

@_cdecl("__kk_system_getProperty")
public func __kk_system_getProperty(_ propertyNameRaw: Int) -> Int {
    guard let propertyName = runtimeStringFromRaw(propertyNameRaw) else {
        return runtimeNullSentinelInt
    }
    let value = runtimeSystemProperties[propertyName]
        ?? ProcessInfo.processInfo.environment[propertyName]
    guard let value else { return runtimeNullSentinelInt }
    return runtimeMakeStringRaw(value)
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

private let processStartNanosValue: Int = Int(clamping: DispatchTime.now().uptimeNanoseconds)

@_cdecl("__kk_system_process_start_nanos")
public func __kk_system_process_start_nanos() -> Int {
    processStartNanosValue
}
