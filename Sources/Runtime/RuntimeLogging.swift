import Foundation

final class RuntimeLoggerBox {
    let name: String
    var handlers: [Int] = []

    init(name: String) {
        self.name = name
    }
}

final class RuntimeLoggerRegistryBox: @unchecked Sendable {
    static let shared = RuntimeLoggerRegistryBox()

    private let lock = NSLock()
    private var loggers: [String: Int] = [:]

    func loggerRaw(named name: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let existing = loggers[name] {
            return existing
        }
        let raw = registerRuntimeObject(RuntimeLoggerBox(name: name))
        loggers[name] = raw
        return raw
    }
}

enum RuntimeLogHandlerKind {
    case console
    case file(path: String)
}

final class RuntimeLogHandlerBox {
    let kind: RuntimeLogHandlerKind

    init(kind: RuntimeLogHandlerKind) {
        self.kind = kind
    }
}

private func runtimeLoggerBox(from raw: Int) -> RuntimeLoggerBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeLoggerBox.self)
}

private func runtimeLogHandlerBox(from raw: Int) -> RuntimeLogHandlerBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeLogHandlerBox.self)
}

private func loggingString(from raw: Int, caller: StaticString) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let value = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
    }
    return value
}

private func loggingMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { ptr in
            kk_string_from_utf8(ptr, Int32(value.utf8.count))
        }
    })
}

private func loggingThrowableMessage(from raw: Int, caller: StaticString) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let throwable = tryCast(ptr, to: RuntimeThrowableBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid Throwable handle")
    }
    return throwable.message
}

private func renderLogLine(
    level: String,
    loggerName: String,
    message: String,
    throwableMessage: String? = nil
) -> String {
    if let throwableMessage {
        return "[\(level)] \(loggerName): \(message) | \(throwableMessage)"
    }
    return "[\(level)] \(loggerName): \(message)"
}

private func publishLog(
    _ logger: RuntimeLoggerBox,
    level: String,
    message: String,
    throwableMessage: String? = nil
) {
    let line = renderLogLine(
        level: level,
        loggerName: logger.name,
        message: message,
        throwableMessage: throwableMessage
    )
    if logger.handlers.isEmpty {
        print(line)
        return
    }
    for handlerRaw in logger.handlers {
        guard let handler = runtimeLogHandlerBox(from: handlerRaw) else { continue }
        switch handler.kind {
        case .console:
            print(line)
        case let .file(path):
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    if let data = (line + "\n").data(using: .utf8) {
                        try? handle.write(contentsOf: data)
                    }
                    try? handle.close()
                }
            } else {
                try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

@_cdecl("kk_logger_getLogger")
public func kk_logger_getLogger(_ nameRaw: Int) -> Int {
    RuntimeLoggerRegistryBox.shared.loggerRaw(named: loggingString(from: nameRaw, caller: #function))
}

@_cdecl("kk_logging_level_info")
public func kk_logging_level_info() -> Int { loggingMakeStringRaw("INFO") }

@_cdecl("kk_logging_level_config")
public func kk_logging_level_config() -> Int { loggingMakeStringRaw("CONFIG") }

@_cdecl("kk_logging_level_fine")
public func kk_logging_level_fine() -> Int { loggingMakeStringRaw("FINE") }

@_cdecl("kk_logging_level_finer")
public func kk_logging_level_finer() -> Int { loggingMakeStringRaw("FINER") }

@_cdecl("kk_logging_level_finest")
public func kk_logging_level_finest() -> Int { loggingMakeStringRaw("FINEST") }

@_cdecl("kk_logging_level_warning")
public func kk_logging_level_warning() -> Int { loggingMakeStringRaw("WARNING") }

@_cdecl("kk_logging_level_severe")
public func kk_logging_level_severe() -> Int { loggingMakeStringRaw("SEVERE") }

@_cdecl("kk_console_handler_new")
public func kk_console_handler_new() -> Int {
    registerRuntimeObject(RuntimeLogHandlerBox(kind: .console))
}

@_cdecl("kk_file_handler_new")
public func kk_file_handler_new(_ pathRaw: Int) -> Int {
    registerRuntimeObject(RuntimeLogHandlerBox(kind: .file(path: loggingString(from: pathRaw, caller: #function))))
}

@_cdecl("kk_logger_addHandler")
public func kk_logger_addHandler(_ loggerRaw: Int, _ handlerRaw: Int) -> Int {
    guard let logger = runtimeLoggerBox(from: loggerRaw),
          runtimeLogHandlerBox(from: handlerRaw) != nil
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_logger_addHandler received invalid handle")
    }
    logger.handlers.append(handlerRaw)
    return 0
}

@_cdecl("kk_logger_log")
public func kk_logger_log(_ loggerRaw: Int, _ levelRaw: Int, _ messageRaw: Int) -> Int {
    guard let logger = runtimeLoggerBox(from: loggerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_logger_log received invalid Logger handle")
    }
    publishLog(
        logger,
        level: loggingString(from: levelRaw, caller: #function),
        message: loggingString(from: messageRaw, caller: #function)
    )
    return 0
}

@_cdecl("kk_logger_log_throwable")
public func kk_logger_log_throwable(
    _ loggerRaw: Int,
    _ levelRaw: Int,
    _ messageRaw: Int,
    _ throwableRaw: Int
) -> Int {
    guard let logger = runtimeLoggerBox(from: loggerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_logger_log_throwable received invalid Logger handle")
    }
    publishLog(
        logger,
        level: loggingString(from: levelRaw, caller: #function),
        message: loggingString(from: messageRaw, caller: #function),
        throwableMessage: loggingThrowableMessage(from: throwableRaw, caller: #function)
    )
    return 0
}

@_cdecl("kk_logger_info")
public func kk_logger_info(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    kk_logger_log(loggerRaw, kk_logging_level_info(), messageRaw)
}

@_cdecl("kk_logger_warning")
public func kk_logger_warning(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    kk_logger_log(loggerRaw, kk_logging_level_warning(), messageRaw)
}

@_cdecl("kk_logger_severe")
public func kk_logger_severe(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    kk_logger_log(loggerRaw, kk_logging_level_severe(), messageRaw)
}

// MARK: - SLF4J-style Logger (TRACE/DEBUG/INFO/WARN/ERROR)

/// Thread-safe numeric log level ordering for SLF4J-compatible logger.
enum SLF4JLevel: Int, Comparable {
    case trace = 0
    case debug = 1
    case info  = 2
    case warn  = 3
    case error = 4

    var label: String {
        switch self {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info:  return "INFO"
        case .warn:  return "WARN"
        case .error: return "ERROR"
        }
    }

    static func < (lhs: SLF4JLevel, rhs: SLF4JLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

final class SLF4JLoggerBox {
    let name: String
    var minimumLevel: SLF4JLevel = .trace

    init(name: String) {
        self.name = name
    }
}

final class SLF4JLoggerRegistryBox: @unchecked Sendable {
    static let shared = SLF4JLoggerRegistryBox()

    private let lock = NSLock()
    private var loggers: [String: Int] = [:]

    func loggerRaw(named name: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let existing = loggers[name] {
            return existing
        }
        let raw = registerRuntimeObject(SLF4JLoggerBox(name: name))
        loggers[name] = raw
        return raw
    }
}

private func slf4jLoggerBox(from raw: Int) -> SLF4JLoggerBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: SLF4JLoggerBox.self)
}

/// Replace `{}` placeholders in `pattern` with successive elements of `args`.
private func slf4jFormat(pattern: String, args: [String]) -> String {
    var result = ""
    result.reserveCapacity(pattern.count)
    var argIndex = 0
    var idx = pattern.startIndex
    while idx < pattern.endIndex {
        let next = pattern.index(after: idx)
        if pattern[idx] == "{", next < pattern.endIndex, pattern[next] == "}" {
            if argIndex < args.count {
                result.append(contentsOf: args[argIndex])
                argIndex += 1
            } else {
                result.append("{}")
            }
            idx = pattern.index(after: next)
        } else {
            result.append(pattern[idx])
            idx = next
        }
    }
    return result
}

private func publishSLF4J(logger: SLF4JLoggerBox, level: SLF4JLevel, message: String) {
    guard level >= logger.minimumLevel else { return }
    let line = "[\(level.label)] \(logger.name): \(message)"
    if level >= .warn {
        var standardError = FileHandle.standardError
        print(line, to: &standardError)
    } else {
        print(line)
    }
}

extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.write(data)
        }
    }
}

// MARK: - LoggerFactory C entry points

@_cdecl("kk_slf4j_logger_get")
public func kk_slf4j_logger_get(_ nameRaw: Int) -> Int {
    SLF4JLoggerRegistryBox.shared.loggerRaw(
        named: loggingString(from: nameRaw, caller: #function)
    )
}

// MARK: - Log-level entry points

@_cdecl("kk_slf4j_log_trace")
public func kk_slf4j_log_trace(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    publishSLF4J(
        logger: logger, level: .trace,
        message: loggingString(from: messageRaw, caller: #function)
    )
    return 0
}

@_cdecl("kk_slf4j_log_debug")
public func kk_slf4j_log_debug(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    publishSLF4J(
        logger: logger, level: .debug,
        message: loggingString(from: messageRaw, caller: #function)
    )
    return 0
}

@_cdecl("kk_slf4j_log_info")
public func kk_slf4j_log_info(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    publishSLF4J(
        logger: logger, level: .info,
        message: loggingString(from: messageRaw, caller: #function)
    )
    return 0
}

@_cdecl("kk_slf4j_log_warn")
public func kk_slf4j_log_warn(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    publishSLF4J(
        logger: logger, level: .warn,
        message: loggingString(from: messageRaw, caller: #function)
    )
    return 0
}

@_cdecl("kk_slf4j_log_error")
public func kk_slf4j_log_error(_ loggerRaw: Int, _ messageRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    publishSLF4J(
        logger: logger, level: .error,
        message: loggingString(from: messageRaw, caller: #function)
    )
    return 0
}

// MARK: - Format helpers (SLF4J {} placeholder substitution)

/// Format a log message with one `{}` argument and log at the requested level.
@_cdecl("kk_slf4j_log_trace_1")
public func kk_slf4j_log_trace_1(_ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [loggingString(from: arg0Raw, caller: #function)]
    )
    publishSLF4J(logger: logger, level: .trace, message: message)
    return 0
}

@_cdecl("kk_slf4j_log_debug_1")
public func kk_slf4j_log_debug_1(_ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [loggingString(from: arg0Raw, caller: #function)]
    )
    publishSLF4J(logger: logger, level: .debug, message: message)
    return 0
}

@_cdecl("kk_slf4j_log_info_1")
public func kk_slf4j_log_info_1(_ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [loggingString(from: arg0Raw, caller: #function)]
    )
    publishSLF4J(logger: logger, level: .info, message: message)
    return 0
}

@_cdecl("kk_slf4j_log_warn_1")
public func kk_slf4j_log_warn_1(_ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [loggingString(from: arg0Raw, caller: #function)]
    )
    publishSLF4J(logger: logger, level: .warn, message: message)
    return 0
}

@_cdecl("kk_slf4j_log_error_1")
public func kk_slf4j_log_error_1(_ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [loggingString(from: arg0Raw, caller: #function)]
    )
    publishSLF4J(logger: logger, level: .error, message: message)
    return 0
}

/// Format a log message with two `{}` arguments.
@_cdecl("kk_slf4j_log_info_2")
public func kk_slf4j_log_info_2(
    _ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int, _ arg1Raw: Int
) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [
            loggingString(from: arg0Raw, caller: #function),
            loggingString(from: arg1Raw, caller: #function),
        ]
    )
    publishSLF4J(logger: logger, level: .info, message: message)
    return 0
}

@_cdecl("kk_slf4j_log_warn_2")
public func kk_slf4j_log_warn_2(
    _ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int, _ arg1Raw: Int
) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [
            loggingString(from: arg0Raw, caller: #function),
            loggingString(from: arg1Raw, caller: #function),
        ]
    )
    publishSLF4J(logger: logger, level: .warn, message: message)
    return 0
}

@_cdecl("kk_slf4j_log_error_2")
public func kk_slf4j_log_error_2(
    _ loggerRaw: Int, _ patternRaw: Int, _ arg0Raw: Int, _ arg1Raw: Int
) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    let message = slf4jFormat(
        pattern: loggingString(from: patternRaw, caller: #function),
        args: [
            loggingString(from: arg0Raw, caller: #function),
            loggingString(from: arg1Raw, caller: #function),
        ]
    )
    publishSLF4J(logger: logger, level: .error, message: message)
    return 0
}

// MARK: - Minimum-level control

@_cdecl("kk_slf4j_set_level")
public func kk_slf4j_set_level(_ loggerRaw: Int, _ levelRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    switch levelRaw {
    case 0: logger.minimumLevel = .trace
    case 1: logger.minimumLevel = .debug
    case 2: logger.minimumLevel = .info
    case 3: logger.minimumLevel = .warn
    case 4: logger.minimumLevel = .error
    default: break
    }
    return 0
}

@_cdecl("kk_slf4j_is_trace_enabled")
public func kk_slf4j_is_trace_enabled(_ loggerRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    return logger.minimumLevel <= .trace ? 1 : 0
}

@_cdecl("kk_slf4j_is_debug_enabled")
public func kk_slf4j_is_debug_enabled(_ loggerRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    return logger.minimumLevel <= .debug ? 1 : 0
}

@_cdecl("kk_slf4j_is_info_enabled")
public func kk_slf4j_is_info_enabled(_ loggerRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    return logger.minimumLevel <= .info ? 1 : 0
}

@_cdecl("kk_slf4j_is_warn_enabled")
public func kk_slf4j_is_warn_enabled(_ loggerRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    return logger.minimumLevel <= .warn ? 1 : 0
}

@_cdecl("kk_slf4j_is_error_enabled")
public func kk_slf4j_is_error_enabled(_ loggerRaw: Int) -> Int {
    guard let logger = slf4jLoggerBox(from: loggerRaw) else { return 0 }
    return logger.minimumLevel <= .error ? 1 : 0
}
