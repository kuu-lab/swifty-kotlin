import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - kotlin.io.path.Path Runtime

final class RuntimeUserPrincipalBox {
    let name: String
    init(name: String) { self.name = name }
}

private func runtimeUserPrincipalBox(from raw: Int) -> RuntimeUserPrincipalBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeUserPrincipalBox.self)
}

final class RuntimePathBox {
    let pathString: String
    init(_ pathString: String) { self.pathString = pathString }
}

private func runtimePathBox(from raw: Int) -> RuntimePathBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimePathBox.self)
}

/// Split file content into lines, matching Kotlin behaviour:
/// - Empty string returns an empty array (not `[""]`).
/// - A trailing newline does NOT produce a final empty element.
private func pathSplitLines(_ content: String) -> [String] {
    if content.isEmpty { return [] }
    var lines = content.components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    return lines
}

private func pathMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

private func pathStringValue(from raw: Int) -> String? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return extractString(from: ptr)
}

private func pathCreateTempDirectoryRaw(
    directoryPath: String,
    prefix: String,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let name = "\(prefix)\(UUID().uuidString)"
    let fullPath = (directoryPath as NSString).appendingPathComponent(name)
    do {
        try FileManager.default.createDirectory(atPath: fullPath, withIntermediateDirectories: false)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return registerRuntimeObject(RuntimePathBox(fullPath))
}

private func pathCreateTempFileRaw(
    directoryPath: String,
    prefix: String,
    suffix: String,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let name = "\(prefix)\(UUID().uuidString)\(suffix)"
    let fullPath = (directoryPath as NSString).appendingPathComponent(name)
    let created = FileManager.default.createFile(atPath: fullPath, contents: nil)
    if !created {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Failed to create temp file \(fullPath)")
    }
    return registerRuntimeObject(RuntimePathBox(fullPath))
}

private func pathLineElements(from raw: Int) -> [Int]? {
    if let list = runtimeListBox(from: raw) {
        return list.elements
    }
    if let array = runtimeArrayBox(from: raw) {
        return array.elements
    }
    return nil
}

private func pathStringEncoding(for charsetRaw: Int) -> String.Encoding {
    switch charsetRaw {
    case 1:
        .isoLatin1
    case 2:
        .ascii
    case 3:
        .utf16
    case 4:
        .utf16BigEndian
    case 5:
        .utf16LittleEndian
    case 6:
        .utf32
    case 7:
        .utf32BigEndian
    case 8:
        .utf32LittleEndian
    default:
        .utf8
    }
}

/// Split a path string into name components, excluding root "/" and empty segments.
private func pathComponents(_ pathString: String) -> [String] {
    pathString.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
}

private enum PathCopyActionResult: Int {
    case continueCopying = 0
    case skipSubtree = 1
    case terminate = 2
}

private enum PathRecursiveCopyControl: Error {
    case terminated
    case thrown(Int)
}

private struct PathWalkRuntimeOptions {
    var breadthFirst = false
    var followLinks = false
}

private let pathWalkOptionBreadthFirstOrdinal = 0
private let pathWalkOptionFollowLinksOrdinal = 1

private func pathWalkOptionOrdinals(from raw: Int) -> [Int] {
    guard raw != 0, raw != runtimeNullSentinelInt else {
        return []
    }
    if let array = runtimeArrayBox(from: raw) {
        return array.elements.map { kk_unbox_int($0) }
    }
    if let list = runtimeListBox(from: raw) {
        return list.elements.map { kk_unbox_int($0) }
    }
    if let set = runtimeSetBox(from: raw) {
        return set.elements.map { kk_unbox_int($0) }
    }
    return [kk_unbox_int(raw)]
}

private func pathWalkOptions(from raw: Int) -> PathWalkRuntimeOptions {
    var options = PathWalkRuntimeOptions()
    for ordinal in pathWalkOptionOrdinals(from: raw) {
        switch ordinal {
        case pathWalkOptionBreadthFirstOrdinal:
            options.breadthFirst = true
        case pathWalkOptionFollowLinksOrdinal:
            options.followLinks = true
        default:
            continue
        }
    }
    return options
}

private func pathIsSymbolicLink(_ path: String, fileManager: FileManager = .default) -> Bool {
    let type = (try? fileManager.attributesOfItem(atPath: path)[.type]) as? FileAttributeType
    return type == .typeSymbolicLink
}

private func pathWalkDirectoryKey(_ path: String, followLinks: Bool) -> String {
    let url = URL(fileURLWithPath: path)
    return (followLinks ? url.resolvingSymlinksInPath() : url)
        .standardizedFileURL
        .path
}

private func pathWalkIsTraversableDirectory(
    _ path: String,
    followLinks: Bool,
    fileManager: FileManager = .default
) -> Bool {
    if pathIsSymbolicLink(path, fileManager: fileManager), !followLinks {
        return false
    }
    var isDirectory: ObjCBool = false
    let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
    return exists && isDirectory.boolValue
}

private func pathWalkChildren(
    of path: String,
    fileManager: FileManager = .default
) -> [String] {
    guard let entries = try? fileManager.contentsOfDirectory(atPath: path) else {
        return []
    }
    return entries
        .sorted()
        .map { (path as NSString).appendingPathComponent($0) }
}

private func pathWalkAppendDepthFirst(
    path: String,
    options: PathWalkRuntimeOptions,
    visitedDirectories: inout Set<String>,
    results: inout [Int],
    fileManager: FileManager = .default
) {
    results.append(registerRuntimeObject(RuntimePathBox(path)))

    guard pathWalkIsTraversableDirectory(path, followLinks: options.followLinks, fileManager: fileManager) else {
        return
    }
    let directoryKey = pathWalkDirectoryKey(path, followLinks: options.followLinks)
    guard visitedDirectories.insert(directoryKey).inserted else {
        return
    }

    for child in pathWalkChildren(of: path, fileManager: fileManager) {
        pathWalkAppendDepthFirst(
            path: child,
            options: options,
            visitedDirectories: &visitedDirectories,
            results: &results,
            fileManager: fileManager
        )
    }
}

private func pathWalkBreadthFirst(
    root: String,
    options: PathWalkRuntimeOptions,
    fileManager: FileManager = .default
) -> [Int] {
    var results: [Int] = []
    var visitedDirectories: Set<String> = []
    var queue = [root]
    var index = 0

    while index < queue.count {
        let path = queue[index]
        index += 1
        results.append(registerRuntimeObject(RuntimePathBox(path)))

        guard pathWalkIsTraversableDirectory(path, followLinks: options.followLinks, fileManager: fileManager) else {
            continue
        }
        let directoryKey = pathWalkDirectoryKey(path, followLinks: options.followLinks)
        guard visitedDirectories.insert(directoryKey).inserted else {
            continue
        }
        queue.append(contentsOf: pathWalkChildren(of: path, fileManager: fileManager))
    }

    return results
}

private func pathDefaultCopyAction(sourceURL: URL, targetURL: URL) throws {
    let fileManager = FileManager.default
    var isSourceDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isSourceDirectory) else {
        throw NSError(
            domain: "KSwiftKRuntimePath",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Source path does not exist: \(sourceURL.path)"]
        )
    }

    if isSourceDirectory.boolValue {
        var isTargetDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: targetURL.path, isDirectory: &isTargetDirectory) {
            if isTargetDirectory.boolValue {
                return
            }
            throw NSError(
                domain: "KSwiftKRuntimePath",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Target path already exists: \(targetURL.path)"]
            )
        }
        try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: false)
    } else {
        if fileManager.fileExists(atPath: targetURL.path) {
            throw NSError(
                domain: "KSwiftKRuntimePath",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Target path already exists: \(targetURL.path)"]
            )
        }
        try fileManager.copyItem(at: sourceURL, to: targetURL)
    }
}

private func pathInvokeCopyAction(
    _ copyActionRaw: Int,
    sourceURL: URL,
    targetURL: URL
) throws -> PathCopyActionResult {
    if copyActionRaw == 0 {
        try pathDefaultCopyAction(sourceURL: sourceURL, targetURL: targetURL)
        return .continueCopying
    }

    let sourceRaw = registerRuntimeObject(RuntimePathBox(sourceURL.path))
    let targetRaw = registerRuntimeObject(RuntimePathBox(targetURL.path))
    var thrown = 0
    let resultRaw = kk_function_invoke_3(copyActionRaw, 0, sourceRaw, targetRaw, &thrown)
    if thrown != 0 {
        throw PathRecursiveCopyControl.thrown(thrown)
    }
    return PathCopyActionResult(rawValue: resultRaw) ?? .continueCopying
}

private func pathCopyItemRecursivelyWithAction(
    sourceURL: URL,
    targetURL: URL,
    copyActionRaw: Int
) throws {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
        throw NSError(
            domain: "KSwiftKRuntimePath",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Source path does not exist: \(sourceURL.path)"]
        )
    }

    let actionResult = try pathInvokeCopyAction(copyActionRaw, sourceURL: sourceURL, targetURL: targetURL)
    switch actionResult {
    case .continueCopying:
        break
    case .skipSubtree:
        return
    case .terminate:
        throw PathRecursiveCopyControl.terminated
    }

    guard isDirectory.boolValue else {
        return
    }
    let children = try fileManager.contentsOfDirectory(
        at: sourceURL,
        includingPropertiesForKeys: nil,
        options: []
    )
    for child in children {
        try pathCopyItemRecursivelyWithAction(
            sourceURL: child,
            targetURL: targetURL.appendingPathComponent(child.lastPathComponent),
            copyActionRaw: copyActionRaw
        )
    }
}

private func pathCopyItemRecursively(sourceURL: URL, targetURL: URL, overwrite: Bool) throws {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
        throw NSError(
            domain: "KSwiftKRuntimePath",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Source path does not exist: \(sourceURL.path)"]
        )
    }

    if fileManager.fileExists(atPath: targetURL.path) {
        if overwrite {
            try fileManager.removeItem(at: targetURL)
        } else {
            throw NSError(
                domain: "KSwiftKRuntimePath",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Target path already exists: \(targetURL.path)"]
            )
        }
    }

    if isDirectory.boolValue {
        try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
        let children = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: nil,
            options: []
        )
        for child in children {
            try pathCopyItemRecursively(
                sourceURL: child,
                targetURL: targetURL.appendingPathComponent(child.lastPathComponent),
                overwrite: overwrite
            )
        }
    } else {
        try fileManager.copyItem(at: sourceURL, to: targetURL)
    }
}

// MARK: - Path(pathString: String) constructor

@_cdecl("kk_path_new")
public func kk_path_new(_ pathStringRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: pathStringRaw),
          let pathString = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_new received invalid pathString")
    }
    return registerRuntimeObject(RuntimePathBox(pathString))
}

// MARK: - Path properties

@_cdecl("kk_path_name")
public func kk_path_name(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_name received invalid Path handle")
    }
    return pathMakeStringRaw((path.pathString as NSString).lastPathComponent)
}

@_cdecl("kk_path_invariantSeparatorsPath")
public func kk_path_invariantSeparatorsPath(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_invariantSeparatorsPath received invalid Path handle")
    }
    return pathMakeStringRaw(path.pathString.replacingOccurrences(of: "\\", with: "/"))
}

@_cdecl("kk_path_invariantSeparatorsPathString")
public func kk_path_invariantSeparatorsPathString(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_invariantSeparatorsPathString received invalid Path handle")
    }
    return pathMakeStringRaw(path.pathString.replacingOccurrences(of: "\\", with: "/"))
}

@_cdecl("kk_path_pathString")
public func kk_path_pathString(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_pathString received invalid Path handle")
    }
    return pathMakeStringRaw(path.pathString)
}

@_cdecl("kk_path_fileName")
public func kk_path_fileName(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_fileName received invalid Path handle")
    }
    let lastComponent = (path.pathString as NSString).lastPathComponent
    if lastComponent.isEmpty || lastComponent == "/" {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimePathBox(lastComponent))
}

@_cdecl("kk_path_parent")
public func kk_path_parent(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_parent received invalid Path handle")
    }
    let parent = (path.pathString as NSString).deletingLastPathComponent
    // Root paths like "/" or "" have no meaningful parent
    if parent.isEmpty || parent == path.pathString {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimePathBox(parent))
}

@_cdecl("kk_path_root")
public func kk_path_root(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_root received invalid Path handle")
    }
    if path.pathString.hasPrefix("/") {
        return registerRuntimeObject(RuntimePathBox("/"))
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_path_nameCount")
public func kk_path_nameCount(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_nameCount received invalid Path handle")
    }
    let components = pathComponents(path.pathString)
    return kk_box_int(components.count)
}

// MARK: - Path.toString()

@_cdecl("kk_path_toString")
public func kk_path_toString(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_toString received invalid Path handle")
    }
    return pathMakeStringRaw(path.pathString)
}

// MARK: - Path.resolve()

@_cdecl("kk_path_resolve_string")
public func kk_path_resolve_string(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_resolve_string received invalid Path handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: otherRaw),
          let other = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_resolve_string received invalid other string")
    }
    let resolved = (path.pathString as NSString).appendingPathComponent(other)
    return registerRuntimeObject(RuntimePathBox(resolved))
}

@_cdecl("kk_path_resolve_path")
public func kk_path_resolve_path(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let otherPath = runtimePathBox(from: otherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_resolve_path received invalid other Path handle")
    }
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_resolve_path received invalid Path handle")
    }
    let resolved = (path.pathString as NSString).appendingPathComponent(otherPath.pathString)
    return registerRuntimeObject(RuntimePathBox(resolved))
}

// MARK: - Path query methods

@_cdecl("kk_path_exists")
public func kk_path_exists(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_exists received invalid Path handle")
    }
    return kk_box_bool(FileManager.default.fileExists(atPath: path.pathString) ? 1 : 0)
}

/// Path.notExists(vararg options: LinkOption): Boolean
///
/// Returns `true` only when the runtime can positively determine that the
/// file system entry at `path` does **not** exist. If the existence check
/// itself cannot be performed (which Kotlin/JVM reports by returning
/// `false`), this entry mirrors that behaviour. The `optionsRaw` parameter
/// matches the Sema-declared `vararg options: LinkOption` shape and is
/// accepted for ABI symmetry with `kk_path_exists` (link options have no
/// effect on the macOS Foundation-backed runtime today).
@_cdecl("kk_path_notExists")
public func kk_path_notExists(_ pathRaw: Int, _ optionsRaw: Int) -> Int {
    _ = optionsRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_notExists received invalid Path handle")
    }
    return kk_box_bool(FileManager.default.fileExists(atPath: path.pathString) ? 0 : 1)
}

@_cdecl("kk_path_isDirectory")
public func kk_path_isDirectory(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_isDirectory received invalid Path handle")
    }
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path.pathString, isDirectory: &isDir)
    return kk_box_bool(exists && isDir.boolValue ? 1 : 0)
}

@_cdecl("kk_path_isRegularFile")
public func kk_path_isRegularFile(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_isRegularFile received invalid Path handle")
    }
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path.pathString, isDirectory: &isDir)
    return kk_box_bool(exists && !isDir.boolValue ? 1 : 0)
}

// MARK: - Path read/write methods

@_cdecl("kk_path_readText")
public func kk_path_readText(_ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_readText received invalid Path handle")
    }
    do {
        let content = try String(contentsOfFile: path.pathString, encoding: .utf8)
        return pathMakeStringRaw(content)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return pathMakeStringRaw("")
    }
}

@_cdecl("kk_path_writeText")
public func kk_path_writeText(_ pathRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_writeText received invalid Path handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: textRaw),
          let text = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_writeText received invalid text")
    }
    do {
        try text.write(toFile: path.pathString, atomically: true, encoding: .utf8)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("kk_path_appendText_default")
public func kk_path_appendText_default(_ pathRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_path_appendText(pathRaw, textRaw, 0, outThrown)
}

@_cdecl("kk_path_appendText")
public func kk_path_appendText(
    _ pathRaw: Int,
    _ textRaw: Int,
    _ charsetRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendText received invalid Path handle")
    }
    guard let text = pathStringValue(from: textRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendText received invalid text")
    }

    let encoding = pathStringEncoding(for: charsetRaw)
    do {
        if FileManager.default.fileExists(atPath: path.pathString) {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path.pathString))
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: text.data(using: encoding) ?? Data(text.utf8))
        } else {
            try text.write(toFile: path.pathString, atomically: true, encoding: encoding)
        }
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

@_cdecl("kk_path_copyTo_options")
public func kk_path_copyTo_options(
    _ pathRaw: Int,
    _ targetRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = optionsRaw
    guard let source = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyTo_options received invalid source Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyTo_options received invalid target Path handle")
    }
    do {
        try FileManager.default.copyItem(atPath: source.pathString, toPath: target.pathString)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return targetRaw
}

@_cdecl("kk_path_copyTo_overwrite")
public func kk_path_copyTo_overwrite(
    _ pathRaw: Int,
    _ targetRaw: Int,
    _ overwriteRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let source = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyTo_overwrite received invalid source Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyTo_overwrite received invalid target Path handle")
    }
    do {
        if kk_unbox_bool(overwriteRaw) != 0,
           FileManager.default.fileExists(atPath: target.pathString) {
            try FileManager.default.removeItem(atPath: target.pathString)
        }
        try FileManager.default.copyItem(atPath: source.pathString, toPath: target.pathString)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return targetRaw
}

@_cdecl("kk_path_appendLines_iterable_default")
public func kk_path_appendLines_iterable_default(_ pathRaw: Int, _ linesRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_path_appendLines_iterable(pathRaw, linesRaw, 0, outThrown)
}

@_cdecl("kk_path_appendLines_iterable")
public func kk_path_appendLines_iterable(_ pathRaw: Int, _ linesRaw: Int, _ charsetRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendLines_iterable received invalid Path handle")
    }
    guard let elements = pathLineElements(from: linesRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendLines_iterable received invalid Iterable handle")
    }
    do {
        let text = elements.map { pathStringValue(from: $0) ?? "null" }.map { $0 + "\n" }.joined()
        let encoding = pathStringEncoding(for: charsetRaw)
        let url = URL(fileURLWithPath: path.pathString)
        if FileManager.default.fileExists(atPath: path.pathString) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = text.data(using: encoding) ?? text.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } else {
            try text.write(toFile: path.pathString, atomically: true, encoding: encoding)
        }
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

@_cdecl("kk_path_writeLines_iterable")
public func kk_path_writeLines_iterable(
    _ pathRaw: Int,
    _ linesRaw: Int,
    _ charsetRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = optionsRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_writeLines_iterable received invalid Path handle")
    }
    guard let elements = pathLineElements(from: linesRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_writeLines_iterable received invalid Iterable handle")
    }
    let text = elements.map { pathStringValue(from: $0) ?? "null" }.map { $0 + "\n" }.joined()
    let encoding = pathStringEncoding(for: charsetRaw)
    do {
        try text.write(toFile: path.pathString, atomically: true, encoding: encoding)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

@_cdecl("kk_path_appendBytes")
public func kk_path_appendBytes(_ pathRaw: Int, _ arrayRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendBytes received invalid Path handle")
    }
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendBytes received invalid ByteArray handle")
    }
    do {
        let url = URL(fileURLWithPath: path.pathString)
        let data = Data(array.elements.map { UInt8(truncatingIfNeeded: $0) })
        if FileManager.default.fileExists(atPath: path.pathString) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("kk_path_readLines")
public func kk_path_readLines(_ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_readLines received invalid Path handle")
    }
    do {
        let content = try String(contentsOfFile: path.pathString, encoding: .utf8)
        let lines = pathSplitLines(content)
        return registerRuntimeObject(RuntimeListBox(elements: lines.map { pathMakeStringRaw($0) }))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
}

@_cdecl("kk_path_bufferedReader")
public func kk_path_bufferedReader(
    _ pathRaw: Int,
    _ charsetRaw: Int,
    _ bufferSizeRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_bufferedReader received invalid Path handle")
    }
    _ = charsetRaw
    _ = optionsRaw
    let bufferSize = max(1, kk_unbox_int(bufferSizeRaw))
    do {
        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path.pathString))
        return registerRuntimeObject(RuntimeBufferedReaderBox(fileHandle: fileHandle, chunkSize: bufferSize))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return 0
    }
}

// MARK: - Path filesystem operations

@_cdecl("kk_path_createDirectories")
public func kk_path_createDirectories(_ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_createDirectories received invalid Path handle")
    }
    do {
        _ = try FileManager.default.createDirectory(atPath: path.pathString, withIntermediateDirectories: true)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    // Returns the Path itself (this)
    return pathRaw
}

@_cdecl("kk_path_createDirectories_attributes")
public func kk_path_createDirectories_attributes(
    _ pathRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    _ = attributesRaw
    return kk_path_createDirectories(pathRaw, outThrown)
}

@_cdecl("kk_path_createDirectory_attributes")
public func kk_path_createDirectory_attributes(
    _ pathRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_createDirectory_attributes received invalid Path handle")
    }
    _ = attributesRaw
    do {
        _ = try FileManager.default.createDirectory(atPath: path.pathString, withIntermediateDirectories: false)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

@_cdecl("kk_path_createFile_attributes")
public func kk_path_createFile_attributes(
    _ pathRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_createFile_attributes received invalid Path handle")
    }
    _ = attributesRaw
    if FileManager.default.fileExists(atPath: path.pathString) {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: file already exists")
        return pathRaw
    }
    let created = FileManager.default.createFile(atPath: path.pathString, contents: Data())
    if !created {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: failed to create file")
    }
    return pathRaw
}

@_cdecl("kk_path_createParentDirectories_attributes")
public func kk_path_createParentDirectories_attributes(
    _ pathRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_createParentDirectories_attributes received invalid Path handle")
    }
    _ = attributesRaw
    let parentPath = (path.pathString as NSString).deletingLastPathComponent
    guard !parentPath.isEmpty, parentPath != path.pathString else {
        return pathRaw
    }
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: parentPath, isDirectory: &isDirectory) {
        if !isDirectory.boolValue {
            outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: parent exists and is not a directory")
        }
        return pathRaw
    }
    do {
        _ = try FileManager.default.createDirectory(atPath: parentPath, withIntermediateDirectories: true)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

@_cdecl("kk_path_createSymbolicLinkPointingTo_attributes")
public func kk_path_createSymbolicLinkPointingTo_attributes(
    _ pathRaw: Int,
    _ targetRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_createSymbolicLinkPointingTo_attributes received invalid Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_createSymbolicLinkPointingTo_attributes received invalid target Path handle")
    }
    _ = attributesRaw
    do {
        try FileManager.default.createSymbolicLink(atPath: path.pathString, withDestinationPath: target.pathString)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

@_cdecl("kk_path_createTempDirectory_directory_prefix_attributes")
public func kk_path_createTempDirectory_directory_prefix_attributes(
    _ directoryRaw: Int,
    _ prefixRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = attributesRaw
    let directoryPath = runtimePathBox(from: directoryRaw)?.pathString ?? FileManager.default.temporaryDirectory.path
    let prefix = pathStringValue(from: prefixRaw) ?? "tmp"
    return pathCreateTempDirectoryRaw(
        directoryPath: directoryPath,
        prefix: prefix,
        outThrown: outThrown
    )
}

@_cdecl("kk_path_createTempDirectory_prefix_attributes")
public func kk_path_createTempDirectory_prefix_attributes(
    _ prefixRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = attributesRaw
    let prefix = pathStringValue(from: prefixRaw) ?? "tmp"
    return pathCreateTempDirectoryRaw(
        directoryPath: FileManager.default.temporaryDirectory.path,
        prefix: prefix,
        outThrown: outThrown
    )
}

@_cdecl("kk_path_createTempFile_directory_prefix_suffix_attributes")
public func kk_path_createTempFile_directory_prefix_suffix_attributes(
    _ directoryRaw: Int,
    _ prefixRaw: Int,
    _ suffixRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = attributesRaw
    let directoryPath = runtimePathBox(from: directoryRaw)?.pathString ?? FileManager.default.temporaryDirectory.path
    let prefix = pathStringValue(from: prefixRaw) ?? "tmp"
    let suffix = pathStringValue(from: suffixRaw) ?? ".tmp"
    return pathCreateTempFileRaw(
        directoryPath: directoryPath,
        prefix: prefix,
        suffix: suffix,
        outThrown: outThrown
    )
}

@_cdecl("kk_path_createTempFile_prefix_suffix_attributes")
public func kk_path_createTempFile_prefix_suffix_attributes(
    _ prefixRaw: Int,
    _ suffixRaw: Int,
    _ attributesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = attributesRaw
    let prefix = pathStringValue(from: prefixRaw) ?? "tmp"
    let suffix = pathStringValue(from: suffixRaw) ?? ".tmp"
    return pathCreateTempFileRaw(
        directoryPath: FileManager.default.temporaryDirectory.path,
        prefix: prefix,
        suffix: suffix,
        outThrown: outThrown
    )
}

@_cdecl("kk_path_deleteIfExists")
public func kk_path_deleteIfExists(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_deleteIfExists received invalid Path handle")
    }
    guard FileManager.default.fileExists(atPath: path.pathString) else {
        return kk_box_bool(0)
    }
    return kk_box_bool((try? FileManager.default.removeItem(atPath: path.pathString)) != nil ? 1 : 0)
}

@_cdecl("kk_path_copyToRecursively_overwrite")
public func kk_path_copyToRecursively_overwrite(
    _ pathRaw: Int,
    _ targetRaw: Int,
    _ onErrorRaw: Int,
    _ followLinksRaw: Int,
    _ overwriteRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = onErrorRaw
    _ = followLinksRaw
    guard let source = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyToRecursively_overwrite received invalid source Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyToRecursively_overwrite received invalid target Path handle")
    }

    do {
        try pathCopyItemRecursively(
            sourceURL: URL(fileURLWithPath: source.pathString),
            targetURL: URL(fileURLWithPath: target.pathString),
            overwrite: kk_unbox_bool(overwriteRaw) != 0
        )
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return targetRaw
}

@_cdecl("kk_path_copyToRecursively_copyAction")
public func kk_path_copyToRecursively_copyAction(
    _ pathRaw: Int,
    _ targetRaw: Int,
    _ onErrorRaw: Int,
    _ followLinksRaw: Int,
    _ copyActionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = onErrorRaw
    _ = followLinksRaw
    guard let source = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyToRecursively_copyAction received invalid source Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_copyToRecursively_copyAction received invalid target Path handle")
    }

    do {
        try pathCopyItemRecursivelyWithAction(
            sourceURL: URL(fileURLWithPath: source.pathString),
            targetURL: URL(fileURLWithPath: target.pathString),
            copyActionRaw: copyActionRaw
        )
    } catch let control as PathRecursiveCopyControl {
        switch control {
        case .terminated:
            break
        case let .thrown(thrownRaw):
            outThrown?.pointee = thrownRaw
        }
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return targetRaw
}

@_cdecl("kk_path_listDirectoryEntries")
public func kk_path_listDirectoryEntries(_ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_listDirectoryEntries received invalid Path handle")
    }
    do {
        let entries = try FileManager.default.contentsOfDirectory(atPath: path.pathString)
        let elements = entries.map { entry -> Int in
            let childPath = (path.pathString as NSString).appendingPathComponent(entry)
            return registerRuntimeObject(RuntimePathBox(childPath))
        }
        return registerRuntimeObject(RuntimeListBox(elements: elements))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
}

/// Path.walk(vararg options: PathWalkOption): Sequence<Path>
///
/// The runtime materialises the walk as a list, which is accepted by the
/// Sequence terminal operations through `runtimeSequenceSourceElements`.
@_cdecl("kk_path_walk")
public func kk_path_walk(_ pathRaw: Int, _ optionsRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_walk received invalid Path handle")
    }
    let options = pathWalkOptions(from: optionsRaw)
    let elements: [Int]
    if options.breadthFirst {
        elements = pathWalkBreadthFirst(root: path.pathString, options: options)
    } else {
        var visitedDirectories: Set<String> = []
        var depthFirstElements: [Int] = []
        pathWalkAppendDepthFirst(
            path: path.pathString,
            options: options,
            visitedDirectories: &visitedDirectories,
            results: &depthFirstElements
        )
        elements = depthFirstElements
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

// MARK: - Path.relativize(other: Path)

@_cdecl("kk_path_relativize")
public func kk_path_relativize(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let base = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_relativize received invalid Path handle")
    }
    guard let other = runtimePathBox(from: otherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_relativize received invalid other Path handle")
    }
    let baseComponents = pathComponents(base.pathString)
    let otherComponents = pathComponents(other.pathString)

    var commonLength = 0
    while commonLength < baseComponents.count && commonLength < otherComponents.count
        && baseComponents[commonLength] == otherComponents[commonLength] {
        commonLength += 1
    }

    let ups = Array(repeating: "..", count: baseComponents.count - commonLength)
    let remainder = Array(otherComponents[commonLength...])
    let relativePath = (ups + remainder).joined(separator: "/")
    return registerRuntimeObject(RuntimePathBox(relativePath.isEmpty ? "." : relativePath))
}

// MARK: - Path.normalize()

@_cdecl("kk_path_normalize")
public func kk_path_normalize(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_normalize received invalid Path handle")
    }
    let isAbsolute = path.pathString.hasPrefix("/")
    var components: [String] = []
    for part in path.pathString.split(separator: "/", omittingEmptySubsequences: true) {
        let s = String(part)
        if s == "." {
            continue
        } else if s == ".." {
            if !components.isEmpty && components.last != ".." {
                components.removeLast()
            } else if !isAbsolute {
                components.append(s)
            }
        } else {
            components.append(s)
        }
    }
    let normalized = (isAbsolute ? "/" : "") + components.joined(separator: "/")
    return registerRuntimeObject(RuntimePathBox(normalized.isEmpty ? "." : normalized))
}

// MARK: - Path comparison methods

@_cdecl("kk_path_startsWith_path")
public func kk_path_startsWith_path(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_startsWith received invalid Path handle")
    }
    guard let other = runtimePathBox(from: otherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_startsWith received invalid other Path handle")
    }
    let pathParts = pathComponents(path.pathString)
    let otherParts = pathComponents(other.pathString)
    let pathIsAbsolute = path.pathString.hasPrefix("/")
    let otherIsAbsolute = other.pathString.hasPrefix("/")
    guard pathIsAbsolute == otherIsAbsolute, otherParts.count <= pathParts.count else {
        return kk_box_bool(0)
    }
    for i in 0..<otherParts.count {
        // swiftlint:disable:next for_where
        if pathParts[i] != otherParts[i] { return kk_box_bool(0) }
    }
    return kk_box_bool(1)
}

@_cdecl("kk_path_startsWith_string")
public func kk_path_startsWith_string(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: otherRaw),
          let otherStr = extractString(from: ptr) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_startsWith_string received invalid string")
    }
    let otherPath = registerRuntimeObject(RuntimePathBox(otherStr))
    return kk_path_startsWith_path(pathRaw, otherPath)
}

@_cdecl("kk_path_endsWith_path")
public func kk_path_endsWith_path(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_endsWith received invalid Path handle")
    }
    guard let other = runtimePathBox(from: otherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_endsWith received invalid other Path handle")
    }
    let pathParts = pathComponents(path.pathString)
    let otherParts = pathComponents(other.pathString)
    // If other is absolute, it must match from root
    if other.pathString.hasPrefix("/") {
        guard path.pathString.hasPrefix("/"), otherParts.count <= pathParts.count else {
            return kk_box_bool(0)
        }
        for i in 0..<otherParts.count {
            // swiftlint:disable:next for_where
            if pathParts[i] != otherParts[i] { return kk_box_bool(0) }
        }
        return kk_box_bool(1)
    }
    guard otherParts.count <= pathParts.count else {
        return kk_box_bool(0)
    }
    let offset = pathParts.count - otherParts.count
    for i in 0..<otherParts.count {
        // swiftlint:disable:next for_where
        if pathParts[offset + i] != otherParts[i] { return kk_box_bool(0) }
    }
    return kk_box_bool(1)
}

@_cdecl("kk_path_endsWith_string")
public func kk_path_endsWith_string(_ pathRaw: Int, _ otherRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: otherRaw),
          let otherStr = extractString(from: ptr) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_endsWith_string received invalid string")
    }
    let otherPath = registerRuntimeObject(RuntimePathBox(otherStr))
    return kk_path_endsWith_path(pathRaw, otherPath)
}

// MARK: - Path conversion methods

@_cdecl("kk_path_toFile")
public func kk_path_toFile(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_toFile received invalid Path handle")
    }
    return registerRuntimeObject(RuntimeFileBox(path.pathString))
}

@_cdecl("kk_path_toUri")
public func kk_path_toUri(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_toUri received invalid Path handle")
    }
    let absolutePath: String
    if path.pathString.hasPrefix("/") {
        absolutePath = path.pathString
    } else {
        absolutePath = (FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent(path.pathString)
    }
    let uriString = "file://" + absolutePath
    if var components = URLComponents(string: uriString) {
        components.scheme = "file"
        return registerRuntimeObject(RuntimeURIBox(components: components))
    }
    // Fallback: create from raw string
    var fallback = URLComponents()
    fallback.scheme = "file"
    fallback.path = absolutePath
    return registerRuntimeObject(RuntimeURIBox(components: fallback))
}

/// kotlin.io.path.toPath() extension on java.net.URI.
///
/// Maps the URI (which must have a "file" scheme) to a Path instance. The
/// implementation mirrors `Paths.get(URI)` in semantics: only file: URIs are
/// supported, and the resulting Path is the URI's decoded path component.
@_cdecl("kk_uri_toPath")
public func kk_uri_toPath(_ uriRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: uriRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_uri_toPath received invalid URI handle")
    }
    guard let uriBox = tryCast(ptr, to: RuntimeURIBox.self) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_uri_toPath received invalid URI handle")
    }
    // Prefer URL-based decoding when available so percent-encoded path
    // characters are translated back to their literal form, matching JVM
    // Paths.get(URI) behaviour for "file" URIs.
    if let url = uriBox.components.url, url.isFileURL {
        return registerRuntimeObject(RuntimePathBox(url.path))
    }
    let path = uriBox.components.path
    return registerRuntimeObject(RuntimePathBox(path))
}

// MARK: - Path.get() / Paths.get() top-level factory

@_cdecl("kk_path_get")
public func kk_path_get(_ pathStringRaw: Int) -> Int {
    return kk_path_new(pathStringRaw)
}

@_cdecl("kk_path_isAbsolute")
public func kk_path_isAbsolute(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_isAbsolute received invalid Path handle")
    }
    return kk_box_bool(path.pathString.hasPrefix("/") ? 1 : 0)
}

@_cdecl("kk_path_toAbsolutePath")
public func kk_path_toAbsolutePath(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_toAbsolutePath received invalid Path handle")
    }
    if path.pathString.hasPrefix("/") {
        return pathRaw
    }
    let absolute = (FileManager.default.currentDirectoryPath as NSString)
        .appendingPathComponent(path.pathString)
    return registerRuntimeObject(RuntimePathBox(absolute))
}

@_cdecl("kk_path_toAbsolutePathString")
public func kk_path_toAbsolutePathString(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_toAbsolutePathString received invalid Path handle")
    }
    if path.pathString.hasPrefix("/") {
        return pathMakeStringRaw(path.pathString)
    }
    let absolute = (FileManager.default.currentDirectoryPath as NSString)
        .appendingPathComponent(path.pathString)
    return pathMakeStringRaw(absolute)
}

@_cdecl("kk_path_getName")
public func kk_path_getName(_ pathRaw: Int, _ indexRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_getName received invalid Path handle")
    }
    let index = kk_unbox_int(indexRaw)
    let components = pathComponents(path.pathString)
    guard index >= 0 && index < components.count else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_getName index out of bounds: \(index)")
    }
    return registerRuntimeObject(RuntimePathBox(components[index]))
}

@_cdecl("kk_path_nameWithoutExtension")
public func kk_path_nameWithoutExtension(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_nameWithoutExtension received invalid Path handle")
    }
    let name = (path.pathString as NSString).lastPathComponent
    guard let dotIndex = name.lastIndex(of: ".") else {
        return pathMakeStringRaw(name)
    }
    return pathMakeStringRaw(String(name[..<dotIndex]))
}

@_cdecl("kk_path_extension")
public func kk_path_extension(_ pathRaw: Int) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_extension received invalid Path handle")
    }
    let name = (path.pathString as NSString).lastPathComponent
    guard let dotIndex = name.lastIndex(of: ".") else {
        return pathMakeStringRaw("")
    }
    return pathMakeStringRaw(String(name[name.index(after: dotIndex)...]))
}

@_cdecl("kk_path_bufferedWriter")
public func kk_path_bufferedWriter(
    _ pathRaw: Int,
    _ charsetRaw: Int,
    _ bufferSizeRaw: Int,
    _ optionsRaw: Int
) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_bufferedWriter received invalid Path handle")
    }
    _ = optionsRaw
    let url = URL(fileURLWithPath: path.pathString)
    if !FileManager.default.fileExists(atPath: path.pathString) {
        _ = FileManager.default.createFile(atPath: path.pathString, contents: Data())
    }
    do {
        let fileHandle = try FileHandle(forWritingTo: url)
        fileHandle.truncateFile(atOffset: 0)
        let bufferSize = max(1, kk_unbox_int(bufferSizeRaw))
        return registerRuntimeObject(RuntimeBufferedWriterBox(
            fileHandle: fileHandle,
            bufferSize: bufferSize,
            encoding: pathStringEncoding(for: charsetRaw)
        ))
    } catch {
        return 0
    }
}

// MARK: - STDLIB-IO-PATH-FN-042: Path.writer

/// Path.writer(charset: Charset = Charsets.UTF_8, vararg options: OpenOption): BufferedWriter
///
/// Opens the file at this path for writing and wraps it in a `BufferedWriter`
/// using the default buffer size (8192 bytes). Truncates any existing content.
/// Throws an IOException-wrapped throwable if the file cannot be opened.
@_cdecl("kk_path_writer")
public func kk_path_writer(
    _ pathRaw: Int,
    _ charsetRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = optionsRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_writer received invalid Path handle")
    }
    let url = URL(fileURLWithPath: path.pathString)
    if !FileManager.default.fileExists(atPath: path.pathString) {
        _ = FileManager.default.createFile(atPath: path.pathString, contents: Data())
    }
    do {
        let fileHandle = try FileHandle(forWritingTo: url)
        fileHandle.truncateFile(atOffset: 0)
        return registerRuntimeObject(RuntimeBufferedWriterBox(
            fileHandle: fileHandle,
            encoding: pathStringEncoding(for: charsetRaw)
        ))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return 0
    }
}

// MARK: - STDLIB-IO-PATH-FN-028: Path.outputStream

/// Path.outputStream(vararg options: OpenOption): OutputStream
///
/// Opens or creates the file at this path and returns a raw byte-level
/// `OutputStream` for writing. The default behaviour (no options) creates or
/// truncates the file. The `optionsRaw` parameter represents the vararg
/// `OpenOption` array and is accepted for ABI symmetry; option values are not
/// inspected by the macOS Foundation-backed runtime today. Returns 0 if the
/// file cannot be opened.
@_cdecl("kk_path_outputStream")
public func kk_path_outputStream(_ pathRaw: Int, _ optionsRaw: Int) -> Int {
    _ = optionsRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_outputStream received invalid Path handle")
    }
    let url = URL(fileURLWithPath: path.pathString)
    if !FileManager.default.fileExists(atPath: path.pathString) {
        _ = FileManager.default.createFile(atPath: path.pathString, contents: Data())
    }
    do {
        let handle = try FileHandle(forWritingTo: url)
        handle.truncateFile(atOffset: 0)
        return registerRuntimeObject(RuntimeOutputStreamBox(fileHandle: handle))
    } catch {
        return 0
    }
}

/// Path.getLastModifiedTime(vararg options: LinkOption): FileTime
///
/// Returns the last-modified time of the file or directory at this path as a
/// `FileTime` (milliseconds since the Unix epoch). The `optionsRaw` parameter
/// represents the vararg `LinkOption` array and is accepted for ABI symmetry;
/// link options have no effect on the macOS Foundation-backed runtime today.
/// Throws an IOException-wrapped throwable if the file attributes cannot be
/// retrieved.
@_cdecl("kk_path_getLastModifiedTime")
public func kk_path_getLastModifiedTime(_ pathRaw: Int, _ optionsRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = optionsRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_getLastModifiedTime received invalid Path handle")
    }
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: path.pathString)
        guard let modDate = attrs[.modificationDate] as? Date else {
            return registerRuntimeObject(RuntimeFileTimeBox(milliseconds: 0))
        }
        return registerRuntimeObject(RuntimeFileTimeBox(milliseconds: Int(modDate.timeIntervalSince1970 * 1000)))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return registerRuntimeObject(RuntimeFileTimeBox(milliseconds: 0))
    }
}

// MARK: - STDLIB-IO-PATH-FN-032: Path.setAttribute

/// Path.setAttribute(attribute: String, value: Any?, vararg options: LinkOption): Path
///
/// Sets a file attribute identified by `attribute`. The attribute string may include a
/// view-name prefix (e.g. `"basic:lastModifiedTime"`); the prefix is stripped before
/// dispatching. Supported attributes on the macOS Foundation-backed runtime:
///   - `lastModifiedTime` — sets the modification date.
///   - `lastAccessTime` — silently accepted; access time cannot be set via Foundation.
///   - `creationTime` — sets the creation date.
///   - All other attribute names cause an `UnsupportedOperationException` throwable.
/// `valueRaw` is resolved as a `RuntimeFileTimeBox` handle if possible; otherwise the
/// string is parsed as milliseconds since the Unix epoch. The `optionsRaw` vararg is
/// accepted for ABI symmetry; link options have no effect on this runtime.
/// Throws an `IOException` if the attribute cannot be applied (e.g. file not found).
@_cdecl("kk_path_setAttribute")
public func kk_path_setAttribute(
    _ pathRaw: Int,
    _ attributeRaw: Int,
    _ valueRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = optionsRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_setAttribute received invalid Path handle")
    }
    guard let attribute = pathStringValue(from: attributeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_setAttribute received invalid attribute handle")
    }

    // Strip optional "view:" prefix (e.g. "basic:lastModifiedTime" → "lastModifiedTime")
    let name: String
    if let colonIndex = attribute.firstIndex(of: ":") {
        name = String(attribute[attribute.index(after: colonIndex)...])
    } else {
        name = attribute
    }

    // Resolve valueRaw as milliseconds since epoch:
    // prefer RuntimeFileTimeBox (for FileTime values), fall back to string-encoded integer.
    // Returns nil if the value cannot be decoded (neither a FileTimeBox nor a parseable integer).
    func resolveMillis() -> Int? {
        if let ptr = UnsafeMutableRawPointer(bitPattern: valueRaw),
           let fileTime = tryCast(ptr, to: RuntimeFileTimeBox.self)
        {
            return fileTime.milliseconds
        }
        guard let str = pathStringValue(from: valueRaw), let parsed = Int(str) else { return nil }
        return parsed
    }

    do {
        switch name {
        case "lastModifiedTime":
            guard let millis = resolveMillis() else {
                outThrown?.pointee = runtimeAllocateIllegalArgumentException(
                    message: "setAttribute('\(attribute)'): value is not a valid FileTime or integer milliseconds"
                )
                return pathRaw
            }
            let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path.pathString)
        case "lastAccessTime":
            // macOS Foundation has no direct setter for access time; verify the path exists
            // so that callers do not silently succeed on missing files.
            guard FileManager.default.fileExists(atPath: path.pathString) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError,
                              userInfo: [NSFilePathErrorKey: path.pathString])
            }
        case "creationTime":
            guard let millis = resolveMillis() else {
                outThrown?.pointee = runtimeAllocateIllegalArgumentException(
                    message: "setAttribute('\(attribute)'): value is not a valid FileTime or integer milliseconds"
                )
                return pathRaw
            }
            let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
            #if canImport(Darwin)
            try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: path.pathString)
            #else
            // Linux filesystems do not expose a settable creation time; verify path exists.
            guard FileManager.default.fileExists(atPath: path.pathString) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError,
                              userInfo: [NSFilePathErrorKey: path.pathString])
            }
            #endif
        default:
            outThrown?.pointee = runtimeAllocateUnsupportedOperationException(
                message: "setAttribute does not support attribute '\(attribute)'"
            )
        }
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

// MARK: - STDLIB-IO-PATH-FN-020: Path.forEachLine

/// Path.forEachLine(action: (String) -> Unit)
///
/// Reads the file at this path and invokes `action` for each line, using the
/// default UTF-8 charset. The line-splitting behaviour mirrors Kotlin stdlib:
/// an empty file produces no invocations, and a trailing newline does not
/// produce a final empty line.
@_cdecl("kk_path_forEachLine_default")
public func kk_path_forEachLine_default(
    _ pathRaw: Int,
    _ actionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_path_forEachLine(pathRaw, 0, actionRaw, outThrown)
}

/// Path.forEachLine(charset: Charset = Charsets.UTF_8, action: (String) -> Unit)
///
/// Reads the file at this path and invokes `action` for each line.
/// `charsetRaw` == 0 selects the default UTF-8 encoding.
@_cdecl("kk_path_forEachLine")
public func kk_path_forEachLine(
    _ pathRaw: Int,
    _ charsetRaw: Int,
    _ actionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_forEachLine received invalid Path handle")
    }
    let encoding = pathStringEncoding(for: charsetRaw)
    guard let content = try? String(contentsOfFile: path.pathString, encoding: encoding) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Cannot read file \(path.pathString)")
        return 0
    }
    let lines = pathSplitLines(content)
    for line in lines {
        let lineRaw = pathMakeStringRaw(line)
        var thrown = 0
        _ = kk_function_invoke(actionRaw, lineRaw, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
    }
    return 0
}

// MARK: - STDLIB-IO-PATH-FN-038: Path.useLines { block }

/// Reads all lines from `path` (using the given charset) and calls `block` once
/// with a `Sequence<String>` containing them.  Mirrors the Kotlin stdlib contract:
///   fun <T> Path.useLines(charset: Charset = Charsets.UTF_8, block: (Sequence<String>) -> T): T
///
/// The sequence is materialised as a RuntimeListBox so it can be passed through
/// the collection HOF closure ABI (fnPtr + closureRaw).
@_cdecl("kk_path_useLines")
public func kk_path_useLines(
    _ pathRaw: Int,
    _ charsetRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_useLines received invalid Path handle")
    }
    let encoding = pathStringEncoding(for: charsetRaw)
    guard let content = try? String(contentsOfFile: path.pathString, encoding: encoding) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IOException: Cannot read file \(path.pathString)"
        )
        return 0
    }
    let lines = pathSplitLines(content)
    let linesListRaw = registerRuntimeObject(
        RuntimeListBox(elements: lines.map { pathMakeStringRaw($0) })
    )
    var thrown = 0
    let result = runtimeInvokeCollectionLambda1(
        fnPtr: fnPtr, closureRaw: closureRaw, value: linesListRaw, outThrown: &thrown
    )
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

/// Default-charset variant of `kk_path_useLines` (UTF-8).
@_cdecl("kk_path_useLines_default")
public func kk_path_useLines_default(
    _ pathRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_path_useLines(pathRaw, 0, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_path_appendLines_sequence_default")
public func kk_path_appendLines_sequence_default(_ pathRaw: Int, _ linesRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_path_appendLines_sequence(pathRaw, linesRaw, 0, outThrown)
}

// MARK: - STDLIB-IO-PATH-FN-019: Path.forEachDirectoryEntry { action }

/// Matches a file name against a simple glob pattern supporting `*` (any sequence)
/// and `?` (any single character).  Mirrors the behaviour of `fnmatch` for the
/// common patterns that Kotlin's `useDirectoryEntries` / `forEachDirectoryEntry`
/// accept (no path-separator escaping needed because these only match bare names).
private func pathMatchesGlob(_ name: String, _ pattern: String) -> Bool {
    var ni = name.startIndex
    var pi = pattern.startIndex
    var starPos: String.Index? = nil
    var matchPos: String.Index? = nil

    while ni < name.endIndex {
        if pi < pattern.endIndex && (pattern[pi] == "?" || pattern[pi] == name[ni]) {
            ni = name.index(after: ni)
            pi = pattern.index(after: pi)
        } else if pi < pattern.endIndex && pattern[pi] == "*" {
            starPos = pi
            matchPos = ni
            pi = pattern.index(after: pi)
        } else if let star = starPos {
            pi = pattern.index(after: star)
            matchPos = name.index(after: matchPos!)
            ni = matchPos!
        } else {
            return false
        }
    }
    while pi < pattern.endIndex && pattern[pi] == "*" {
        pi = pattern.index(after: pi)
    }
    return pi == pattern.endIndex
}

/// Path.forEachDirectoryEntry(glob: String = "*", action: (Path) -> Unit)
///
/// Lists direct children of this directory, filters them by `glob`, and calls
/// `action` once for each matched entry. `globRaw == 0` selects the default
/// `"*"` pattern (all entries).
@_cdecl("kk_path_forEachDirectoryEntry")
public func kk_path_forEachDirectoryEntry(
    _ pathRaw: Int,
    _ globRaw: Int,
    _ actionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_forEachDirectoryEntry received invalid Path handle")
    }
    let glob = globRaw == 0 ? "*" : (pathStringValue(from: globRaw) ?? "*")
    guard let rawEntries = try? FileManager.default.contentsOfDirectory(atPath: path.pathString) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Cannot list directory \(path.pathString)")
        return 0
    }
    let matched = glob == "*" ? rawEntries : rawEntries.filter { pathMatchesGlob($0, glob) }
    for entry in matched {
        let childPath = (path.pathString as NSString).appendingPathComponent(entry)
        let childRaw = registerRuntimeObject(RuntimePathBox(childPath))
        var thrown = 0
        _ = kk_function_invoke(actionRaw, childRaw, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
    }
    return 0
}

/// Default-glob variant of `kk_path_forEachDirectoryEntry` (matches all entries).
@_cdecl("kk_path_forEachDirectoryEntry_default")
public func kk_path_forEachDirectoryEntry_default(
    _ pathRaw: Int,
    _ actionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_path_forEachDirectoryEntry(pathRaw, 0, actionRaw, outThrown)
}

// MARK: - STDLIB-IO-PATH-FN-037: Path.useDirectoryEntries { block }

/// Path.useDirectoryEntries(glob: String = "*", block: (Sequence<Path>) -> T): T
///
/// Lists direct children of this directory, filters them by `glob`, and calls
/// `block` once with a `Sequence<Path>` containing the matched entries.  The
/// return value of `block` is returned to the caller.
///
/// `globRaw == 0` selects the default `"*"` pattern (all entries).
@_cdecl("kk_path_useDirectoryEntries")
public func kk_path_useDirectoryEntries(
    _ pathRaw: Int,
    _ globRaw: Int,
    _ actionRaw: Int
) -> Int {
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_useDirectoryEntries received invalid Path handle")
    }
    let glob = globRaw == 0 ? "*" : (pathStringValue(from: globRaw) ?? "*")
    guard let rawEntries = try? FileManager.default.contentsOfDirectory(atPath: path.pathString) else {
        return 0
    }
    let matched = glob == "*" ? rawEntries : rawEntries.filter { pathMatchesGlob($0, glob) }
    let elements = matched.map { entry -> Int in
        let childPath = (path.pathString as NSString).appendingPathComponent(entry)
        return registerRuntimeObject(RuntimePathBox(childPath))
    }
    let listRaw = registerRuntimeObject(RuntimeListBox(elements: elements))
    var thrown = 0
    return kk_function_invoke(actionRaw, listRaw, &thrown)
}

/// Default-glob variant of `kk_path_useDirectoryEntries` (matches all entries).
@_cdecl("kk_path_useDirectoryEntries_default")
public func kk_path_useDirectoryEntries_default(
    _ pathRaw: Int,
    _ actionRaw: Int
) -> Int {
    kk_path_useDirectoryEntries(pathRaw, 0, actionRaw)
}

// MARK: - STDLIB-IO-PATH-FN-074: Path.visitFileTree(maxDepth, followLinks, builderAction)

final class RuntimeFileVisitorBox {
    var onPreVisitDirectoryRaw: Int = 0
    var onVisitFileRaw: Int = 0
    var onPostVisitDirectoryRaw: Int = 0
}

private func runtimeFileVisitorBox(from raw: Int) -> RuntimeFileVisitorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeFileVisitorBox.self)
}

private enum PathVisitResult {
    case continueVisit
    case terminate
    case skipSubtree
    case skipSiblings

    init(fromRaw raw: Int) {
        switch raw {
        case 1: self = .terminate
        case 2: self = .skipSubtree
        case 3: self = .skipSiblings
        default: self = .continueVisit
        }
    }
}

private func pathVisitEntry(
    url: URL,
    depth: Int,
    maxDepth: Int,
    followLinks: Bool,
    visitor: RuntimeFileVisitorBox,
    fileManager: FileManager,
    outThrown: UnsafeMutablePointer<Int>?
) -> PathVisitResult {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        return .continueVisit
    }

    if isDirectory.boolValue {
        let pathRaw = registerRuntimeObject(RuntimePathBox(url.path))

        if visitor.onPreVisitDirectoryRaw != 0 {
            var thrown = 0
            let resultRaw = kk_function_invoke_2(visitor.onPreVisitDirectoryRaw, pathRaw, 0, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return .terminate
            }
            let result = PathVisitResult(fromRaw: resultRaw)
            switch result {
            case .terminate:
                return .terminate
            case .skipSubtree:
                if visitor.onPostVisitDirectoryRaw != 0 {
                    var thrown2 = 0
                    _ = kk_function_invoke_2(visitor.onPostVisitDirectoryRaw, pathRaw, 0, &thrown2)
                    if thrown2 != 0 { outThrown?.pointee = thrown2 }
                }
                return .continueVisit
            default:
                break
            }
        }

        if depth < maxDepth {
            let children = (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants]
            )) ?? []
            outer: for child in children {
                var childIsDir: ObjCBool = false
                let isSymlink = (try? fileManager.attributesOfItem(atPath: child.path))?[.type] as? FileAttributeType == .typeSymbolicLink
                if isSymlink && !followLinks {
                    continue
                }
                _ = fileManager.fileExists(atPath: child.path, isDirectory: &childIsDir)
                let result = pathVisitEntry(
                    url: child,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    followLinks: followLinks,
                    visitor: visitor,
                    fileManager: fileManager,
                    outThrown: outThrown
                )
                switch result {
                case .terminate:
                    return .terminate
                case .skipSiblings:
                    break outer
                default:
                    break
                }
            }
        }

        if visitor.onPostVisitDirectoryRaw != 0 {
            let pathRaw2 = registerRuntimeObject(RuntimePathBox(url.path))
            var thrown = 0
            let resultRaw = kk_function_invoke_2(visitor.onPostVisitDirectoryRaw, pathRaw2, 0, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return .terminate
            }
            return PathVisitResult(fromRaw: resultRaw)
        }
    } else {
        let pathRaw = registerRuntimeObject(RuntimePathBox(url.path))
        if visitor.onVisitFileRaw != 0 {
            var thrown = 0
            let resultRaw = kk_function_invoke_2(visitor.onVisitFileRaw, pathRaw, 0, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return .terminate
            }
            return PathVisitResult(fromRaw: resultRaw)
        }
    }
    return .continueVisit
}

@_cdecl("kk_path_fileVisitor")
public func kk_path_fileVisitor(_ builderActionRaw: Int) -> Int {
    let visitor = RuntimeFileVisitorBox()
    let visitorRaw = registerRuntimeObject(visitor)
    if builderActionRaw != 0 {
        var thrown = 0
        _ = kk_function_invoke(builderActionRaw, visitorRaw, &thrown)
    }
    return visitorRaw
}

@_cdecl("kk_path_visitFileTree")
public func kk_path_visitFileTree(
    _ pathRaw: Int,
    _ visitorRaw: Int,
    _ maxDepthRaw: Int,
    _ followLinksRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_visitFileTree received invalid Path handle")
    }
    let maxDepth = maxDepthRaw
    let followLinks = followLinksRaw != 0
    let visitor = runtimeFileVisitorBox(from: visitorRaw) ?? RuntimeFileVisitorBox()
    let rootURL = URL(fileURLWithPath: path.pathString)
    _ = pathVisitEntry(
        url: rootURL,
        depth: 0,
        maxDepth: maxDepth,
        followLinks: followLinks,
        visitor: visitor,
        fileManager: .default,
        outThrown: outThrown
    )
    return 0
}

@_cdecl("kk_path_visitFileTree_builder")
public func kk_path_visitFileTree_builder(
    _ pathRaw: Int,
    _ maxDepthRaw: Int,
    _ followLinksRaw: Int,
    _ builderActionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let visitorRaw = kk_path_fileVisitor(builderActionRaw)
    return kk_path_visitFileTree(pathRaw, visitorRaw, maxDepthRaw, followLinksRaw, outThrown)
}

@_cdecl("kk_path_appendLines_sequence")
public func kk_path_appendLines_sequence(_ pathRaw: Int, _ linesRaw: Int, _ charsetRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendLines_sequence received invalid Path handle")
    }
    guard let elements = runtimeSequenceSourceElements(from: linesRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_appendLines_sequence received invalid lines sequence")
    }
    let text = elements.map { pathStringValue(from: $0) ?? "null" }.map { $0 + "\n" }.joined()
    let encoding = pathStringEncoding(for: charsetRaw)
    do {
        if FileManager.default.fileExists(atPath: path.pathString) {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path.pathString))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: text.data(using: encoding) ?? Data(text.utf8))
        } else {
            try text.write(toFile: path.pathString, atomically: true, encoding: encoding)
        }
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

@_cdecl("kk_path_writeLines_sequence")
public func kk_path_writeLines_sequence(
    _ pathRaw: Int,
    _ linesRaw: Int,
    _ charsetRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = optionsRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_writeLines_sequence received invalid Path handle")
    }
    guard let elements = runtimeSequenceSourceElements(from: linesRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_writeLines_sequence received invalid lines sequence")
    }
    let text = elements.map { pathStringValue(from: $0) ?? "null" }.map { $0 + "\n" }.joined()
    let encoding = pathStringEncoding(for: charsetRaw)
    do {
        try text.write(toFile: path.pathString, atomically: true, encoding: encoding)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

// MARK: - STDLIB-IO-PATH-FN-030: Path.readAttributes

/// Runtime box for `java.nio.file.attribute.BasicFileAttributes`.
final class RuntimeBasicFileAttributesBox {
    let lastModifiedTimeMillis: Int
    let lastAccessTimeMillis: Int
    let creationTimeMillis: Int
    let isRegularFile: Bool
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let isOther: Bool
    let size: Int

    init(
        lastModifiedTimeMillis: Int,
        lastAccessTimeMillis: Int,
        creationTimeMillis: Int,
        isRegularFile: Bool,
        isDirectory: Bool,
        isSymbolicLink: Bool,
        isOther: Bool,
        size: Int
    ) {
        self.lastModifiedTimeMillis = lastModifiedTimeMillis
        self.lastAccessTimeMillis = lastAccessTimeMillis
        self.creationTimeMillis = creationTimeMillis
        self.isRegularFile = isRegularFile
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.isOther = isOther
        self.size = size
    }
}

private func pathReadBasicFileAttributes(_ pathString: String) -> RuntimeBasicFileAttributesBox? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: pathString) else {
        return nil
    }
    let fileType = attrs[.type] as? FileAttributeType
    let isDir = fileType == .typeDirectory
    let isRegular = fileType == .typeRegular
    let isSymlink = fileType == .typeSymbolicLink
    let isOther = !isDir && !isRegular && !isSymlink
    let modDate = attrs[.modificationDate] as? Date
    let createDate = attrs[.creationDate] as? Date
    let modMillis = modDate.map { Int($0.timeIntervalSince1970 * 1000) } ?? 0
    let createMillis = createDate.map { Int($0.timeIntervalSince1970 * 1000) } ?? 0
    let fileSize = (attrs[.size] as? Int) ?? 0
    return RuntimeBasicFileAttributesBox(
        lastModifiedTimeMillis: modMillis,
        lastAccessTimeMillis: modMillis,
        creationTimeMillis: createMillis,
        isRegularFile: isRegular,
        isDirectory: isDir,
        isSymbolicLink: isSymlink,
        isOther: isOther,
        size: fileSize
    )
}

private func pathBuildAttributesMap(
    _ attrsBox: RuntimeBasicFileAttributesBox,
    attrSpec: String
) -> RuntimeMapBox {
    let allAttrs: [(String, Int)] = [
        ("lastModifiedTime", registerRuntimeObject(RuntimeFileTimeBox(milliseconds: attrsBox.lastModifiedTimeMillis))),
        ("lastAccessTime", registerRuntimeObject(RuntimeFileTimeBox(milliseconds: attrsBox.lastAccessTimeMillis))),
        ("creationTime", registerRuntimeObject(RuntimeFileTimeBox(milliseconds: attrsBox.creationTimeMillis))),
        ("isRegularFile", kk_box_bool(attrsBox.isRegularFile ? 1 : 0)),
        ("isDirectory", kk_box_bool(attrsBox.isDirectory ? 1 : 0)),
        ("isSymbolicLink", kk_box_bool(attrsBox.isSymbolicLink ? 1 : 0)),
        ("isOther", kk_box_bool(attrsBox.isOther ? 1 : 0)),
        ("size", kk_box_long(attrsBox.size)),
        ("fileKey", runtimeNullSentinelInt),
    ]
    let selected: [(String, Int)]
    if attrSpec == "*" {
        selected = allAttrs
    } else {
        let requested = Set(attrSpec.split(separator: ",").map(String.init))
        selected = allAttrs.filter { requested.contains($0.0) }
    }
    return RuntimeMapBox(
        keys: selected.map { pathMakeStringRaw($0.0) },
        values: selected.map { $0.1 }
    )
}

/// Path.readAttributes(attributes: String, vararg options: LinkOption): Map<String, Any?>
///
/// Parses the JVM NIO attribute view string (e.g. `"basic:*"`, `"basic:size,isDirectory"`)
/// and returns a map of attribute names to their boxed values.
@_cdecl("kk_path_readAttributes_string")
public func kk_path_readAttributes_string(
    _ pathRaw: Int,
    _ attributesRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = optionsRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_readAttributes_string received invalid Path handle")
    }
    let attrString = pathStringValue(from: attributesRaw) ?? "basic:*"
    let parts = attrString.split(separator: ":", maxSplits: 1)
    let attrSpec = parts.count > 1 ? String(parts[1]) : "*"

    guard let attrsBox = pathReadBasicFileAttributes(path.pathString) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Cannot read attributes of \(path.pathString)")
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    return registerRuntimeObject(pathBuildAttributesMap(attrsBox, attrSpec: attrSpec))
}

/// Path.readAttributes<A : BasicFileAttributes>(vararg options: LinkOption): A
///
/// Returns a `BasicFileAttributes` box for the file at this path.
@_cdecl("kk_path_readAttributes")
public func kk_path_readAttributes(
    _ pathRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = optionsRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_readAttributes received invalid Path handle")
    }
    guard let attrsBox = pathReadBasicFileAttributes(path.pathString) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Cannot read attributes of \(path.pathString)")
        return 0
    }
    return registerRuntimeObject(attrsBox)
}

// MARK: - STDLIB-IO-PATH-FN-023: Path.getOwner / Path.setOwner

/// Path.getOwner(vararg options: LinkOption): UserPrincipal
///
/// Returns the owner of the file at this path as a `UserPrincipal`. The
/// `optionsRaw` parameter represents the vararg `LinkOption` array and is
/// accepted for ABI symmetry; link options have no effect on the macOS
/// Foundation-backed runtime today.
/// Throws an IOException-wrapped throwable if the file attributes cannot be
/// retrieved.
@_cdecl("kk_path_getOwner")
public func kk_path_getOwner(
    _ pathRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = optionsRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_getOwner received invalid Path handle")
    }
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: path.pathString)
        guard let ownerName = attrs[.ownerAccountName] as? String else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IOException: Cannot determine file owner for \(path.pathString)"
            )
            return 0
        }
        return registerRuntimeObject(RuntimeUserPrincipalBox(name: ownerName))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return 0
    }
}

/// Path.setOwner(value: UserPrincipal): Path
///
/// Sets the owner of the file at this path to the user represented by the
/// given `UserPrincipal`. Uses POSIX `getpwnam_r` to resolve the principal's
/// name to a UID, then calls `chown` to apply the change.
/// Throws an IOException-wrapped throwable if the owner cannot be set.
@_cdecl("kk_path_setOwner")
public func kk_path_setOwner(
    _ pathRaw: Int,
    _ ownerRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_setOwner received invalid Path handle")
    }
    guard let principal = runtimeUserPrincipalBox(from: ownerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_setOwner received invalid UserPrincipal handle")
    }
    var pwStorage = passwd()
    var buffer = [CChar](repeating: 0, count: 1024)
    var pwResult: UnsafeMutablePointer<passwd>? = nil
    let errno = getpwnam_r(principal.name, &pwStorage, &buffer, buffer.count, &pwResult)
    guard errno == 0, pwResult != nil else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IOException: Unknown user '\(principal.name)'"
        )
        return pathRaw
    }
    let uid = pwStorage.pw_uid
    // Pass ~gid_t(0) (all-bits-set) to preserve the existing group, per POSIX chown(2).
    if chown(path.pathString, uid, ~gid_t(0)) != 0 {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IOException: Cannot set owner for \(path.pathString)"
        )
    }
    return pathRaw
}

@_cdecl("kk_path_moveTo_overwrite")
public func kk_path_moveTo_overwrite(
    _ pathRaw: Int,
    _ targetRaw: Int,
    _ overwriteRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let source = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_moveTo_overwrite received invalid source Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_moveTo_overwrite received invalid target Path handle")
    }
    do {
        if kk_unbox_bool(overwriteRaw) != 0,
           FileManager.default.fileExists(atPath: target.pathString) {
            try FileManager.default.removeItem(atPath: target.pathString)
        }
        try FileManager.default.moveItem(atPath: source.pathString, toPath: target.pathString)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return targetRaw
}

@_cdecl("kk_path_moveTo_options")
public func kk_path_moveTo_options(
    _ pathRaw: Int,
    _ targetRaw: Int,
    _ optionsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    _ = optionsRaw
    guard let source = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_moveTo_options received invalid source Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_path_moveTo_options received invalid target Path handle")
    }
    do {
        try FileManager.default.moveItem(atPath: source.pathString, toPath: target.pathString)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return targetRaw
}
