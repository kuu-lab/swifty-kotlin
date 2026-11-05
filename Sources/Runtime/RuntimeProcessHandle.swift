import Foundation
import RuntimeABI

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Decodes a NUL-terminated `[CChar]` buffer as UTF-8; the array-taking
/// `String(cString:)` overload is deprecated.
private func runtimeUTF8String(fromCString buffer: [CChar]) -> String {
    let end = buffer.firstIndex(of: 0) ?? buffer.count
    return String(decoding: buffer[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

#if canImport(Darwin)
    private func runtimeDarwinBsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let count = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        return count == size ? info : nil
    }

    /// `proc_pidpath` resolves the executable even for processes whose argv[0]
    /// was a bare command name; nil when the process is gone or not ours.
    private func runtimeProcessCommandPath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return runtimeUTF8String(fromCString: buffer)
    }

    /// `KERN_PROCARGS2` returns argc followed by the exec path and then argc
    /// argument strings. Kernel tasks and processes owned by other users may
    /// be unreadable; nil then maps to empty `ProcessHandle.Info` fields.
    private func runtimeProcessArguments(_ pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        let argc = bytes.withUnsafeBytes { $0.load(as: Int32.self) }
        var offset = MemoryLayout<Int32>.size
        // Skip the executable path string, then the NUL padding before argv.
        while offset < size, bytes[offset] != 0 { offset += 1 }
        offset += 1
        while offset < size, bytes[offset] == 0 { offset += 1 }
        var arguments: [String] = []
        var index = 0
        while offset < size, index < Int(argc) {
            var end = offset
            while end < size, bytes[end] != 0 { end += 1 }
            if end > offset {
                arguments.append(String(decoding: bytes[offset ..< end], as: UTF8.self))
            }
            offset = end + 1
            index += 1
        }
        return arguments.isEmpty ? nil : arguments
    }

    private func runtimeProcessStartEpochMillis(_ pid: pid_t) -> Int64 {
        guard let info = runtimeDarwinBsdInfo(pid) else { return 0 }
        return Int64(info.pbi_start_tvsec) * 1000 + Int64(info.pbi_start_tvusec) / 1000
    }

    private func runtimeProcessCpuNanos(_ pid: pid_t) -> Int64 {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        guard result == 0 else { return -1 }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = Int64(info.ri_user_time) + Int64(info.ri_system_time)
        return ticks * Int64(timebase.numer) / Int64(timebase.denom)
    }

    private func runtimeProcessUserName(_ pid: pid_t) -> String? {
        guard let info = runtimeDarwinBsdInfo(pid) else { return nil }
        guard let passwd = getpwuid(info.pbi_uid) else { return nil }
        return String(cString: passwd.pointee.pw_name)
    }

    /// (pid, ppid) pairs for every process visible to this user, used by
    /// `ProcessHandle.children()`/`descendants()`/`parent()`/`allProcesses()`.
    func runtimeCollectProcessPairs() -> [(pid_t, pid_t)] {
        let size = proc_listallpids(nil, 0)
        guard size > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(size) / MemoryLayout<pid_t>.stride)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        let pidCount = Int(count) / MemoryLayout<pid_t>.stride
        var pairs: [(pid_t, pid_t)] = []
        pairs.reserveCapacity(pidCount)
        for pid in pids.prefix(pidCount) where pid > 0 {
            guard let info = runtimeDarwinBsdInfo(pid) else { continue }
            pairs.append((pid, pid_t(info.pbi_ppid)))
        }
        return pairs
    }

#elseif canImport(Glibc)
    /// Fields of `/proc/<pid>/stat` after the closing paren of comm:
    /// index 0 = state (field 3), 1 = ppid (4), 11 = utime (14),
    /// 12 = stime (15), 19 = starttime (22, clock ticks since boot).
    private func runtimeLinuxStatFields(_ pid: pid_t) -> [Substring]? {
        guard let text = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
              let closeIndex = text.lastIndex(of: ")")
        else { return nil }
        let rest = text[text.index(after: closeIndex)...]
        let fields = rest.split(separator: " ")
        return fields.isEmpty ? nil : fields
    }

    private func runtimeLinuxPpid(_ pid: pid_t) -> pid_t? {
        guard let fields = runtimeLinuxStatFields(pid), fields.count > 1 else { return nil }
        return pid_t(fields[1])
    }

    private func runtimeProcessCommandPath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let count = readlink("/proc/\(pid)/exe", &buffer, buffer.count - 1)
        guard count > 0 else { return nil }
        buffer[count] = 0
        return runtimeUTF8String(fromCString: buffer)
    }

    /// `/proc/<pid>/cmdline` is NUL-separated argv; kernel threads have an
    /// empty file which maps to nil (no arguments available).
    private func runtimeProcessArguments(_ pid: pid_t) -> [String]? {
        guard let data = FileManager.default.contents(atPath: "/proc/\(pid)/cmdline"),
              !data.isEmpty
        else { return nil }
        let arguments = data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        return arguments.isEmpty ? nil : arguments
    }

    private func runtimeLinuxBootTimeSeconds() -> Int64 {
        guard let text = try? String(contentsOfFile: "/proc/stat", encoding: .utf8) else { return 0 }
        for line in text.split(separator: "\n") where line.hasPrefix("btime ") {
            return Int64(line.dropFirst(6)) ?? 0
        }
        return 0
    }

    private func runtimeLinuxClockTicksPerSecond() -> Int64 {
        let ticks = sysconf(Int32(_SC_CLK_TCK))
        return ticks > 0 ? Int64(ticks) : 100
    }

    private func runtimeProcessStartEpochMillis(_ pid: pid_t) -> Int64 {
        guard let fields = runtimeLinuxStatFields(pid), fields.count > 19,
              let startTicks = Int64(fields[19])
        else { return 0 }
        let seconds = runtimeLinuxBootTimeSeconds() + startTicks / runtimeLinuxClockTicksPerSecond()
        return seconds * 1000
    }

    private func runtimeProcessCpuNanos(_ pid: pid_t) -> Int64 {
        guard let fields = runtimeLinuxStatFields(pid), fields.count > 12,
              let utime = Int64(fields[11]),
              let stime = Int64(fields[12])
        else { return -1 }
        return (utime + stime) * 1_000_000_000 / runtimeLinuxClockTicksPerSecond()
    }

    private func runtimeProcessUserName(_ pid: pid_t) -> String? {
        guard let status = try? String(contentsOfFile: "/proc/\(pid)/status", encoding: .utf8) else { return nil }
        for line in status.split(separator: "\n") where line.hasPrefix("Uid:") {
            let fields = line.split(separator: " ")
            // "Uid:\t<ruid>\t<euid>\t<suid>\t<fsuid>" — the real uid names the owner.
            guard fields.count > 1, let uid = uid_t(String(fields[1])) else { continue }
            guard let passwd = getpwuid(uid) else { return nil }
            return String(cString: passwd.pointee.pw_name)
        }
        return nil
    }

    func runtimeCollectProcessPairs() -> [(pid_t, pid_t)] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: "/proc") else { return [] }
        var pairs: [(pid_t, pid_t)] = []
        for name in names {
            guard let pid = pid_t(name), pid > 0,
                  let ppid = runtimeLinuxPpid(pid)
            else { continue }
            pairs.append((pid, ppid))
        }
        return pairs
    }
#endif

/// `ProcessHandle.of`/`isAlive` probe: registry children answer from their
/// published exit state; foreign processes use `kill(pid, 0)` where EPERM
/// still means "exists".
@_cdecl("__kk_process_handle_alive")
public func __kk_process_handle_alive(_ pid: Int) -> Int {
    let pidValue = pid_t(truncatingIfNeeded: pid)
    guard pidValue > 0 else { return 0 }
    if let box = runtimeProcessRegistry.box(forPid: pidValue) {
        return box.isExited ? 0 : 1
    }
    if kill(pidValue, 0) == 0 { return 1 }
    return errno == EPERM ? 1 : 0
}

/// `ProcessHandle.destroy()`/`destroyForcibly()`: SIGTERM vs SIGKILL. Returns
/// 1 when the signal was delivered (the JDK returns whether termination was
/// initiated, which `kill(2)` success approximates).
@_cdecl("__kk_process_handle_destroy")
public func __kk_process_handle_destroy(_ pid: Int, _ forcible: Int) -> Int {
    let pidValue = pid_t(truncatingIfNeeded: pid)
    guard pidValue > 0 else { return 0 }
    let signal = forcible != 0 ? SIGKILL : SIGTERM
    return kill(pidValue, signal) == 0 ? 1 : 0
}

/// Flat `[pid, ppid, ...]` `List<Long>` for `children`/`descendants`/`parent`/
/// `allProcesses`, built like `__kk_longArray_toList` so generic `List<Long>`
/// consumers unbox correctly.
@_cdecl("__kk_process_handle_table")
public func __kk_process_handle_table() -> Int {
    let pairs = runtimeCollectProcessPairs()
    var elements: [Int] = []
    elements.reserveCapacity(pairs.count * 2)
    for (pid, ppid) in pairs {
        elements.append(kk_box_long_nonnull(Int(pid)))
        elements.append(kk_box_long_nonnull(Int(ppid)))
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("__kk_process_info_command")
public func __kk_process_info_command(_ pid: Int) -> Int {
    guard let path = runtimeProcessCommandPath(pid_t(truncatingIfNeeded: pid)) else {
        return runtimeNullSentinelInt
    }
    return runtimeMakeStringRaw(path)
}

@_cdecl("__kk_process_info_command_line")
public func __kk_process_info_command_line(_ pid: Int) -> Int {
    guard let arguments = runtimeProcessArguments(pid_t(truncatingIfNeeded: pid)),
          !arguments.isEmpty
    else { return runtimeNullSentinelInt }
    return runtimeMakeStringRaw(arguments.joined(separator: " "))
}

/// `ProcessHandle.Info.arguments()` excludes argv[0]; the OS returns full
/// argv, so the first element is dropped here.
@_cdecl("__kk_process_info_arguments")
public func __kk_process_info_arguments(_ pid: Int) -> Int {
    guard let arguments = runtimeProcessArguments(pid_t(truncatingIfNeeded: pid)),
          !arguments.isEmpty
    else { return runtimeNullSentinelInt }
    let box = RuntimeArrayBox(length: arguments.count - 1)
    box.installComponentTypeIfAbsent(__kk_array_component_type(2, 0))
    for (index, argument) in arguments.dropFirst().enumerated() {
        box[index] = registerRuntimeObject(RuntimeStringBox(KotlinStringSurrogateEncoding.encode(argument)))
    }
    let raw = registerRuntimeObject(box)
    runtimeRegisterArrayType(rawValue: raw, typeID: runtimeStableNominalTypeID(fqName: "kotlin.Array"))
    return raw
}

/// Epoch milliseconds; 0 means unknown so Kotlin reports an empty Optional.
@_cdecl("__kk_process_info_start_time")
public func __kk_process_info_start_time(_ pid: Int) -> Int {
    Int(runtimeProcessStartEpochMillis(pid_t(truncatingIfNeeded: pid)))
}

/// CPU nanoseconds; -1 means unknown.
@_cdecl("__kk_process_info_cpu_time")
public func __kk_process_info_cpu_time(_ pid: Int) -> Int {
    Int(runtimeProcessCpuNanos(pid_t(truncatingIfNeeded: pid)))
}

@_cdecl("__kk_process_info_user")
public func __kk_process_info_user(_ pid: Int) -> Int {
    guard let name = runtimeProcessUserName(pid_t(truncatingIfNeeded: pid)) else {
        return runtimeNullSentinelInt
    }
    return runtimeMakeStringRaw(name)
}
