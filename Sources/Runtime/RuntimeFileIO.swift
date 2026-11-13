import Foundation
import RuntimeABI
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif


final class RuntimeFileBox {
    let path: String
    init(_ path: String) { self.path = path }
}

final class RuntimeClassLoaderBox {}

private func runtimeFileBox(from raw: Int) -> RuntimeFileBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeFileBox.self)
}

private func resourceRootDirectory() -> URL {
    if let env = ProcessInfo.processInfo.environment["KSWIFTK_RESOURCE_ROOT"], !env.isEmpty {
        return URL(fileURLWithPath: env, isDirectory: true)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
}

private func resourcePath(named name: String) -> (root: URL, candidate: URL, components: [String])? {
    guard !name.isEmpty else { return nil }
    let root = resourceRootDirectory().standardizedFileURL
    let resolved = root.appendingPathComponent(name).standardizedFileURL
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard resolved.path == root.path || resolved.path.hasPrefix(rootPath) else {
        return nil
    }
    let relativePath = String(resolved.path.dropFirst(rootPath.count))
    let components = relativePath.split(separator: "/").map(String.init)
    return (root, resolved, components)
}

private func openResourceComponents(rootDescriptor: Int32, components: [String]) -> Int32? {
    var directoryDescriptor = rootDescriptor
    for (index, component) in components.enumerated() {
        let isLast = index == components.count - 1
        let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW | (isLast ? 0 : O_DIRECTORY)
        let nextDescriptor = component.withCString {
            openat(directoryDescriptor, $0, flags)
        }
        close(directoryDescriptor)
        guard nextDescriptor >= 0 else { return nil }
        directoryDescriptor = nextDescriptor
    }
    return directoryDescriptor
}

private func openResourceFileDescriptor(named name: String) -> (url: URL, descriptor: Int32)? {
    guard let path = resourcePath(named: name) else { return nil }
    let rootDescriptor = path.root.path.withCString {
        open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    }
    guard rootDescriptor >= 0 else { return nil }

    guard !path.components.isEmpty else {
        return (path.candidate, rootDescriptor)
    }

    #if canImport(Darwin)
    // Let the kernel enforce both no-symlink traversal and beneath-root resolution.
    let relativePath = path.components.joined(separator: "/")
    let descriptor = relativePath.withCString {
        openat(rootDescriptor, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW_ANY | O_RESOLVE_BENEATH)
    }
    let openError = errno
    guard descriptor >= 0 else {
        if openError == EINVAL {
            // Older Darwin kernels may not recognize the resolution flags.
            guard let fallbackDescriptor = openResourceComponents(
                rootDescriptor: rootDescriptor,
                components: path.components
            ) else { return nil }
            return (path.candidate, fallbackDescriptor)
        }
        close(rootDescriptor)
        return nil
    }
    close(rootDescriptor)
    return (path.candidate, descriptor)
    #else
    guard let descriptor = openResourceComponents(
        rootDescriptor: rootDescriptor,
        components: path.components
    ) else { return nil }
    return (path.candidate, descriptor)
    #endif
}

private func readResourceData(from descriptor: Int32) -> Data? {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    while true {
        let count = read(descriptor, &buffer, buffer.count)
        if count == 0 { return data }
        guard count > 0 else { return nil }
        data.append(contentsOf: buffer.prefix(count))
    }
}

private func existingResourceURL(named name: String) -> URL? {
    guard let opened = openResourceFileDescriptor(named: name) else { return nil }
    close(opened.descriptor)
    return opened.url
}

// kotlin.io.createTempDir/createTempFile (Deprecated(level=ERROR), see
// AnnotationSemanticTests.testAnnotationSemanticSema and
// Scripts/diff_cases/deprecated_apis.kt). These are real, still-present
// (if force-deprecated) top-level stdlib functions, not part of File's own
// member facade CLEANUP-STUB-107 removed — restored after being lost as an
// unintended side effect of that cleanup.

private func runtimeOptionalFileIOStringArgument(_ raw: Int) -> String? {
    guard raw != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }
    return extractString(from: ptr).map(KotlinStringSurrogateEncoding.unicodeString)
}

private func runtimeOptionalFileBoxArgument(_ raw: Int) -> RuntimeFileBox? {
    guard raw != runtimeNullSentinelInt else {
        return nil
    }
    return runtimeFileBox(from: raw)
}

private func runtimeDeprecatedTempRootDirectory(directoryRaw: Int) -> String {
    if let directory = runtimeOptionalFileBoxArgument(directoryRaw) {
        return directory.path
    }
    return NSTemporaryDirectory()
}

private func runtimeDeprecatedTempPrefix(_ raw: Int) -> String {
    runtimeOptionalFileIOStringArgument(raw) ?? "tmp"
}

private func runtimeDeprecatedTempSuffix(_ raw: Int, default defaultValue: String) -> String {
    runtimeOptionalFileIOStringArgument(raw) ?? defaultValue
}

private func runtimeCreateDeprecatedTempFile(
    prefixRaw: Int,
    suffixRaw: Int,
    directoryRaw: Int
) throws -> Int {
    let prefix = runtimeDeprecatedTempPrefix(prefixRaw)
    let suffix = runtimeDeprecatedTempSuffix(suffixRaw, default: ".tmp")
    let rootDirectory = runtimeDeprecatedTempRootDirectory(directoryRaw: directoryRaw)
    let fileName = "\(prefix)\(UUID().uuidString)\(suffix)"
    let fullPath = (rootDirectory as NSString).appendingPathComponent(fileName)
    let created = FileManager.default.createFile(atPath: fullPath, contents: nil)
    if !created {
        throw RuntimeThrownHandle(runtimeAllocateFileSystemException(
            file: fullPath,
            reason: "Failed to create the temporary file."
        ))
    }
    return registerRuntimeObject(RuntimeFileBox(fullPath))
}

private func runtimeCreateDeprecatedTempDirectory(
    prefixRaw: Int,
    suffixRaw: Int,
    directoryRaw: Int
) throws -> Int {
    let prefix = runtimeDeprecatedTempPrefix(prefixRaw)
    let suffix = runtimeDeprecatedTempSuffix(suffixRaw, default: ".tmp")
    let rootDirectory = runtimeDeprecatedTempRootDirectory(directoryRaw: directoryRaw)
    let dirName = "\(prefix)\(UUID().uuidString)\(suffix)"
    let fullPath = (rootDirectory as NSString).appendingPathComponent(dirName)
    do {
        _ = try FileManager.default.createDirectory(atPath: fullPath, withIntermediateDirectories: true)
    } catch {
        throw RuntimeThrownHandle(runtimeAllocateFileSystemException(
            file: fullPath,
            reason: error.localizedDescription
        ))
    }
    return registerRuntimeObject(RuntimeFileBox(fullPath))
}

@_cdecl("__kk_io_createTempDir_default")
public func __kk_io_createTempDir_default(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        try runtimeCreateDeprecatedTempDirectory(
            prefixRaw: runtimeNullSentinelInt,
            suffixRaw: runtimeNullSentinelInt,
            directoryRaw: runtimeNullSentinelInt
        )
    }
}

@_cdecl("__kk_io_createTempDir_prefix")
public func __kk_io_createTempDir_prefix(_ prefixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        try runtimeCreateDeprecatedTempDirectory(
            prefixRaw: prefixRaw,
            suffixRaw: runtimeNullSentinelInt,
            directoryRaw: runtimeNullSentinelInt
        )
    }
}

@_cdecl("__kk_io_createTempDir_prefix_suffix")
public func __kk_io_createTempDir_prefix_suffix(_ prefixRaw: Int, _ suffixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        try runtimeCreateDeprecatedTempDirectory(
            prefixRaw: prefixRaw,
            suffixRaw: suffixRaw,
            directoryRaw: runtimeNullSentinelInt
        )
    }
}

@_cdecl("__kk_io_createTempDir")
public func __kk_io_createTempDir(_ prefixRaw: Int, _ suffixRaw: Int, _ directoryRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        try runtimeCreateDeprecatedTempDirectory(
            prefixRaw: prefixRaw,
            suffixRaw: suffixRaw,
            directoryRaw: directoryRaw
        )
    }
}

@_cdecl("__kk_io_createTempFile_default")
public func __kk_io_createTempFile_default(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        try runtimeCreateDeprecatedTempFile(
            prefixRaw: runtimeNullSentinelInt,
            suffixRaw: runtimeNullSentinelInt,
            directoryRaw: runtimeNullSentinelInt
        )
    }
}

@_cdecl("__kk_io_createTempFile_prefix")
public func __kk_io_createTempFile_prefix(_ prefixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        try runtimeCreateDeprecatedTempFile(
            prefixRaw: prefixRaw,
            suffixRaw: runtimeNullSentinelInt,
            directoryRaw: runtimeNullSentinelInt
        )
    }
}

@_cdecl("__kk_io_createTempFile_prefix_suffix")
public func __kk_io_createTempFile_prefix_suffix(_ prefixRaw: Int, _ suffixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        try runtimeCreateDeprecatedTempFile(
            prefixRaw: prefixRaw,
            suffixRaw: suffixRaw,
            directoryRaw: runtimeNullSentinelInt
        )
    }
}

@_cdecl("__kk_io_createTempFile")
public func __kk_io_createTempFile(_ prefixRaw: Int, _ suffixRaw: Int, _ directoryRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        try runtimeCreateDeprecatedTempFile(
            prefixRaw: prefixRaw,
            suffixRaw: suffixRaw,
            directoryRaw: directoryRaw
        )
    }
}


@_cdecl("__kk_file_new")
public func __kk_file_new(_ pathRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: pathRaw),
          let path = extractString(from: ptr).map(KotlinStringSurrogateEncoding.unicodeString)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_new received invalid path")
    }
    return registerRuntimeObject(RuntimeFileBox(path))
}

@_cdecl("__kk_file_new_parent_child")
public func __kk_file_new_parent_child(_ parentRaw: Int, _ childRaw: Int) -> Int {
    guard let parentPtr = UnsafeMutableRawPointer(bitPattern: parentRaw),
          let parent = extractString(from: parentPtr).map(KotlinStringSurrogateEncoding.unicodeString)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_new_parent_child received invalid parent")
    }
    guard let childPtr = UnsafeMutableRawPointer(bitPattern: childRaw),
          let child = extractString(from: childPtr).map(KotlinStringSurrogateEncoding.unicodeString)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_new_parent_child received invalid child")
    }
    let path = (parent as NSString).appendingPathComponent(child)
    return registerRuntimeObject(RuntimeFileBox(path))
}

@_cdecl("__kk_file_readText")
public func __kk_file_readText(
    _ fileRaw: Int,
    _ charsetTag: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeMakeUTF8StringRaw("")) {
        guard let file = runtimeFileBox(from: fileRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_readText received invalid File handle")
        }
        do {
            let content = try String(contentsOfFile: file.path, encoding: outputStreamEncoding(for: charsetTag))
            return runtimeMakeUTF8StringRaw(content)
        } catch {
            throw RuntimeThrownHandle(runtimeAllocateFileSystemException(
                file: file.path,
                reason: error.localizedDescription
            ))
        }
    }
}

@_cdecl("__kk_classloader_getSystemClassLoader")
public func __kk_classloader_getSystemClassLoader() -> Int {
    registerRuntimeObject(RuntimeClassLoaderBox())
}

@_cdecl("__kk_classloader_getResource")
public func __kk_classloader_getResource(_ loaderRaw: Int, _ nameRaw: Int) -> Int {
    guard UnsafeMutableRawPointer(bitPattern: loaderRaw).flatMap({ tryCast($0, to: RuntimeClassLoaderBox.self) }) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_classloader_getResource received invalid ClassLoader handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
          let name = extractString(from: ptr).map(KotlinStringSurrogateEncoding.unicodeString),
          let url = existingResourceURL(named: name)
    else {
        return runtimeNullSentinelInt
    }
    return runtimeMakeUTF8StringRaw(url.path)
}

@_cdecl("__kk_classloader_getResourceAsStream")
public func __kk_classloader_getResourceAsStream(_ loaderRaw: Int, _ nameRaw: Int) -> Int {
    guard UnsafeMutableRawPointer(bitPattern: loaderRaw).flatMap({ tryCast($0, to: RuntimeClassLoaderBox.self) }) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_classloader_getResourceAsStream received invalid ClassLoader handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
          let name = extractString(from: ptr).map(KotlinStringSurrogateEncoding.unicodeString),
          let opened = openResourceFileDescriptor(named: name)
    else {
        return runtimeNullSentinelInt
    }
    defer { close(opened.descriptor) }
    guard let data = readResourceData(from: opened.descriptor) else {
        return runtimeNullSentinelInt
    }
    return runtimeRegisterIoStream(
        RuntimeInputStreamBox(data: data),
        fqName: "java.io.InputStream",
        input: true
    )
}

@_cdecl("__kk_resource_exists")
public func __kk_resource_exists(_ nameRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
          let name = extractString(from: ptr).map(KotlinStringSurrogateEncoding.unicodeString)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_resource_exists received invalid name")
    }
    return kk_box_bool(existingResourceURL(named: name) != nil ? 1 : 0)
}

@_cdecl("__kk_readResourceAsText")
public func __kk_readResourceAsText(_ nameRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeMakeUTF8StringRaw("")) {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
              let name = extractString(from: ptr).map(KotlinStringSurrogateEncoding.unicodeString)
        else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_readResourceAsText received invalid name")
        }
        guard let opened = openResourceFileDescriptor(named: name) else {
            throw RuntimeThrownHandle(runtimeAllocateIOException(message: "Resource not found: \(name)"))
        }
        defer { close(opened.descriptor) }
        do {
            guard let data = readResourceData(from: opened.descriptor),
                  let text = String(data: data, encoding: .utf8)
            else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            return runtimeMakeUTF8StringRaw(text)
        } catch let failure as RuntimeThrownHandle {
            throw failure
        } catch {
            throw RuntimeThrownHandle(runtimeAllocateIOException(message: error.localizedDescription))
        }
    }
}


@_cdecl("__kk_file_path")
public func __kk_file_path(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_path received invalid File handle")
    }
    return runtimeMakeUTF8StringRaw(file.path)
}


private func runtimeBufferedReaderBox(from raw: Int) -> RuntimeBufferedReaderBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeBufferedReaderBox.self)
}

/// Non-box `java.io.Reader` handles are Kotlin-source subclass objects
/// (StringReader, user-defined subclasses). Their nominal typeID + recorded
/// `typeParents` ancestry mark them as `java.io.Reader` assignable, so a
/// vtable-dispatching `RuntimeKotlinReaderCharSource` can read from them
/// (KUU-4031).
func runtimeKotlinReaderCharSource(from raw: Int) -> RuntimeKotlinReaderCharSource? {
    guard raw != runtimeNullSentinelInt,
          let typeID = runtimeObjectTypeID(rawValue: raw),
          runtimeIsAssignable(
              sourceTypeID: typeID,
              targetTypeID: runtimeStableNominalTypeID(fqName: "java.io.Reader")
          )
    else { return nil }
    return RuntimeKotlinReaderCharSource(readerRaw: raw)
}

/// Resolves any `java.io.Reader` handle — a reader box or a Kotlin-source
/// subclass object — to the char source the reader bridges consume.
func runtimeReaderCharSource(from raw: Int) -> (any RuntimeReaderCharSource)? {
    if let reader = runtimeBufferedReaderBox(from: raw) { return reader }
    return runtimeKotlinReaderCharSource(from: raw)
}

private func runtimeInputStreamBox(from raw: Int) -> RuntimeInputStreamBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeInputStreamBox.self)
}

@_cdecl("__kk_input_stream_reader_new")
public func __kk_input_stream_reader_new(_ streamRaw: Int) -> Int {
    let stream = runtimeInputStreamBox(from: streamRaw).map { $0 as any RuntimeReaderInputStream }
        ?? runtimeSequenceInputStreamBox(from: streamRaw).map { $0 as any RuntimeReaderInputStream }
        ?? runtimeKotlinInputStream(from: streamRaw).map { $0 as any RuntimeReaderInputStream }
    guard let stream else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_reader_new received invalid InputStream handle")
    }
    let readerRaw = registerRuntimeObject(RuntimeBufferedReaderBox(inputStream: stream))
    runtimeRegisterJavaReader(readerRaw, fqName: "java.io.InputStreamReader", parentFQName: "java.io.Reader")
    return readerRaw
}

/// Accepts any `java.io.Reader` handle — a reader box (`BufferedReader`,
/// `InputStreamReader`) or a Kotlin-source subclass object such as
/// `StringReader` / a user `Reader` subclass (KUU-4031).
@_cdecl("__kk_buffered_reader_new")
public func __kk_buffered_reader_new(_ readerRaw: Int) -> Int {
    guard let reader = runtimeReaderCharSource(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_new received invalid Reader handle")
    }
    let bufferedReaderRaw = registerRuntimeObject(RuntimeBufferedReaderBox(reader: reader))
    runtimeRegisterJavaReader(bufferedReaderRaw, fqName: "java.io.BufferedReader", parentFQName: "java.io.Reader")
    return bufferedReaderRaw
}

private func runtimeByteArrayBytes(from raw: Int) -> [UInt8]? {
    if let array = runtimeArrayBox(from: raw) {
        return array.elements.map { UInt8(truncatingIfNeeded: $0) }
    }
    if let list = runtimeListBox(from: raw) {
        return list.elements.map { UInt8(truncatingIfNeeded: kk_unbox_int($0)) }
    }
    return nil
}

func runtimeOutputStreamBox(from raw: Int) -> RuntimeOutputStreamBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeOutputStreamBox.self)
}

@_cdecl("__kk_buffered_reader_readLine")
public func __kk_buffered_reader_readLine(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_readLine received invalid BufferedReader handle")
    }
    guard let line = reader.readLine() else {
        return runtimeNullSentinelInt
    }
    return runtimeMakeUTF8StringRaw(line)
}

@_cdecl("__kk_buffered_reader_readLines")
public func __kk_buffered_reader_readLines(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_readLines received invalid BufferedReader handle")
    }
    let lines = reader.readLines()
    return registerRuntimeObject(RuntimeListBox(elements: lines.map { runtimeMakeUTF8StringRaw($0) }))
}

@_cdecl("__kk_buffered_reader_close")
public func __kk_buffered_reader_close(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_close received invalid BufferedReader handle")
    }
    reader.close()
    return 0
}

@_cdecl("__kk_buffered_reader_read")
public func __kk_buffered_reader_read(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_read received invalid BufferedReader handle")
    }
    return reader.read()
}

@_cdecl("__kk_buffered_reader_ready")
public func __kk_buffered_reader_ready(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_ready received invalid BufferedReader handle")
    }
    return kk_box_bool(reader.ready() ? 1 : 0)
}

// The iterator prefetches at most one line per
// `hasNext()`/`next()` pair, so iterating a large file holds only the current
// line instead of draining the whole reader into a list first.
final class RuntimeBufferedLineIteratorBox {
    private let reader: RuntimeBufferedReaderBox
    private var prefetchedLine: String?
    private var finished = false

    init(reader: RuntimeBufferedReaderBox) {
        self.reader = reader
    }

    func hasNext() -> Bool {
        if prefetchedLine == nil, !finished {
            if let line = reader.readLine() {
                prefetchedLine = line
            } else {
                finished = true
            }
        }
        return prefetchedLine != nil
    }

    func next() -> String? {
        guard hasNext() else { return nil }
        defer { prefetchedLine = nil }
        return prefetchedLine
    }
}

func runtimeBufferedLineIteratorBox(from raw: Int) -> RuntimeBufferedLineIteratorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeBufferedLineIteratorBox.self)
}

/// `hasNext`/`next` for the streaming line iterator. These return nil when
/// `iterRaw` holds a different iterator box so the generic `kk_iterator_*` and
/// `__kk_range_*` dispatchers can fall through to the other shapes.
func runtimeBufferedLineIteratorHasNext(_ iterRaw: Int) -> Int? {
    guard let iter = runtimeBufferedLineIteratorBox(from: iterRaw) else { return nil }
    return iter.hasNext() ? 1 : 0
}

func runtimeBufferedLineIteratorNext(
    _ iterRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int? {
    guard let iter = runtimeBufferedLineIteratorBox(from: iterRaw) else { return nil }
    guard let line = iter.next() else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateNoSuchElementException(message: "BufferedReader line iterator has no next element.")
        )
        return 0
    }
    return runtimeMakeUTF8StringRaw(line)
}

@_cdecl("__kk_buffered_reader_iterator")
public func __kk_buffered_reader_iterator(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_iterator received invalid BufferedReader handle")
    }
    return registerRuntimeObject(RuntimeBufferedLineIteratorBox(reader: reader))
}

// Our implementation hands the lambda a `RuntimeSequenceBox` whose pull-source
// reads one line at a time, so the block only buffers what it actually
// materialises.
@_cdecl("__kk_buffered_reader_useLines")
public func __kk_buffered_reader_useLines(_ readerRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_useLines received invalid BufferedReader handle")
        }
        let linesSequence = RuntimeSequenceBox(
            steps: [
                .pullSource {
                    reader.readLine().map(runtimeMakeUTF8StringRaw)
                },
            ],
            constrainOnceState: RuntimeSequenceConstrainOnceState()
        )
        let linesSequenceRaw = registerRuntimeObject(linesSequence)
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: linesSequenceRaw, outThrown: &thrown)
        // Always close the reader to honour the `use { }` contract even on lambda throw.
        reader.close()
        if thrown != 0 {
            throw RuntimeThrownHandle(thrown)
        }
        return result
    }
}

// Iteration stops early when the action throws (the thrown value is propagated
// via `outThrown`). Unlike `useLines`, the reader is NOT automatically closed
// after iteration ends — this mirrors the JVM contract where `forEachLine`
// leaves the reader open.
@_cdecl("__kk_buffered_reader_forEachLine")
public func __kk_buffered_reader_forEachLine(
    _ readerRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
            fatalError(
                "KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_forEachLine received invalid BufferedReader handle"
            )
        }
        // Stream one line at a time: `forEachLine` exists to bound memory while
        // walking large files, so the reader is never drained into a [String].
        while let line = reader.readLine() {
            let lineRaw = runtimeMakeUTF8StringRaw(line)
            var thrown = 0
            _ = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: lineRaw, outThrown: &thrown)
            if thrown != 0 {
                throw RuntimeThrownHandle(thrown)
            }
        }
        return 0
    }
}

// In KSwiftK every concrete `Reader` instance is currently a `BufferedReader`
// so we dispatch to `RuntimeBufferedReaderBox.readText()`. The function does
// NOT close the reader, matching the stdlib contract (callers should pair with
// `use { }`).
// Errors during stream reads bubble up as an empty string with no thrown
// exception, mirroring the lenient behaviour of our other reader helpers
// (`readLine`, `readLines`). The Sema extension signature is `() -> String`,
// so the only ABI argument is the receiver handle — no `outThrown` parameter.
@_cdecl("__kk_reader_readText")
public func __kk_reader_readText(_ readerRaw: Int) -> Int {
    guard let reader = runtimeReaderCharSource(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_reader_readText received invalid Reader handle")
    }
    return runtimeMakeUTF8StringRaw(reader.readText())
}

/// `java.io.Reader.read(CharArray, Int, Int)` — the class's sole virtual
/// member (vtable slot `RuntimeIoStreamVTableSlot.readerReadChars` on box
/// handles; source subclasses land their override in the same slot). Reads
/// UTF-16 code units through the resolved `RuntimeReaderCharSource`, so
/// Kotlin-reader receivers (StringReader, user subclasses) behave exactly
/// like their source-level `read` implementation.
@_cdecl("__kk_reader_read_range")
public func __kk_reader_read_range(
    _ readerRaw: Int,
    _ bufferRaw: Int,
    _ offsetRaw: Int,
    _ lengthRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: -1) {
        guard let source = runtimeReaderCharSource(from: readerRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_reader_read_range received invalid Reader handle")
        }
        guard let array = runtimeArrayBox(from: bufferRaw) else {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "expected CharArray buffer"))
        }
        let offset = offsetRaw
        let length = lengthRaw
        guard offset >= 0, length >= 0, offset <= array.count - length else {
            throw RuntimeThrownHandle(runtimeAllocateIndexOutOfBoundsException(
                message: "offset=\(offset) length=\(length) size=\(array.count)"
            ))
        }
        if length == 0 { return 0 }
        // Kotlin-source readers (StringReader, user `Reader` subclasses) dispatch
        // their own 3-arg implementation straight into the caller's buffer —
        // staging through this transient charSource would buffer up to 4096
        // units per refill and silently drop everything past `length` on the
        // next call (KUU-4044).
        if let kotlinSource = source as? RuntimeKotlinReaderCharSource {
            return kotlinSource.readRangeInto(
                bufferRaw: bufferRaw,
                offset: offset,
                length: length,
                outThrown: outThrown
            )
        }
        var copied = 0
        while copied < length {
            let value = source.read()
            if value < 0 { break }
            array[offset + copied] = value
            copied += 1
        }
        if copied == 0 {
            if let kotlinSource = source as? RuntimeKotlinReaderCharSource, kotlinSource.thrown != 0 {
                throw RuntimeThrownHandle(kotlinSource.thrown)
            }
            return -1
        }
        return copied
    }
}

/// `java.io.Reader.read(CharArray)` (KUU-4044) — the JVM concrete overload
/// that delegates to `read(cbuf, 0, cbuf.length)`. Forwarding to
/// `__kk_reader_read_range` keeps the virtual char-source contract (box fast
/// path or Kotlin-reader vtable source) as the single implementation, so a
/// subclass's 3-arg override still supplies the chars.
@_cdecl("__kk_reader_read")
public func __kk_reader_read(
    _ readerRaw: Int,
    _ bufferRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: -1) {
        guard let array = runtimeArrayBox(from: bufferRaw) else {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "expected CharArray buffer"))
        }
        return __kk_reader_read_range(readerRaw, bufferRaw, 0, array.count, outThrown)
    }
}

//
// The private boundary takes an Int CharsetTag. Source wrappers extract it
// from the public Charset object before invoking this unchanged ABI.
@_cdecl("__kk_input_stream_bufferedReader")
public func __kk_input_stream_bufferedReader(
    _ streamRaw: Int, _ charsetRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown) {
        let bytes = __kk_input_stream_readAllBytes(streamRaw, outThrown)
        if let outThrown, outThrown.pointee != 0 { return 0 }
        let text = __kk_bytearray_decodeToString_charset(bytes, charsetRaw)
        guard let pointer = UnsafeMutableRawPointer(bitPattern: text),
              let decoded = extractString(from: pointer) else { return 0 }
        let utf8 = Data(KotlinStringSurrogateEncoding.unicodeString(decoded).utf8)
        let readerRaw = registerRuntimeObject(RuntimeBufferedReaderBox(data: utf8))
        runtimeRegisterJavaReader(readerRaw, fqName: "java.io.BufferedReader", parentFQName: "java.io.Reader")
        return readerRaw
    }
}


private func runtimeBufferedWriterBox(from raw: Int) -> RuntimeBufferedWriterBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeBufferedWriterBox.self)
}

private func runtimeStringWriterBox(from raw: Int) -> RuntimeStringWriterBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeStringWriterBox.self)
}

private func runtimeStringWriterNew(initialCapacity: Int?) -> Int {
    let builder: RuntimeStringBuilderBox
    if let initialCapacity {
        builder = RuntimeStringBuilderBox(units: [], capacity: initialCapacity)
    } else {
        builder = RuntimeStringBuilderBox()
    }
    let bufferRaw = runtimeRegisterStringBuilderType(registerRuntimeObject(builder))
    return runtimeRegisterJavaWriter(
        RuntimeStringWriterBox(builder: builder, bufferRaw: bufferRaw),
        fqName: "java.io.StringWriter",
        parentFQName: "java.io.Writer"
    )
}

@_cdecl("__kk_string_writer_new_default")
public func __kk_string_writer_new_default() -> Int {
    runtimeStringWriterNew(initialCapacity: nil)
}

@_cdecl("__kk_string_writer_new")
public func __kk_string_writer_new(_ initialSize: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard initialSize >= 0 else {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "negative initial size"))
        }
        return runtimeStringWriterNew(initialCapacity: initialSize)
    }
}

@_cdecl("__kk_string_writer_to_string")
public func __kk_string_writer_to_string(_ writerRaw: Int) -> Int {
    guard let writer = runtimeStringWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_string_writer_to_string received invalid StringWriter handle")
    }
    return runtimeMakeUTF8StringRaw(writer.stringValue())
}

@_cdecl("__kk_string_writer_get_buffer")
public func __kk_string_writer_get_buffer(_ writerRaw: Int) -> Int {
    guard let writer = runtimeStringWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_string_writer_get_buffer received invalid StringWriter handle")
    }
    return writer.bufferRaw
}

@_cdecl("__kk_buffered_writer_write")
public func __kk_buffered_writer_write(_ writerRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        let writer: any RuntimeJavaWriter
        if let bufferedWriter = runtimeBufferedWriterBox(from: writerRaw) {
            writer = bufferedWriter
        } else if let stringWriter = runtimeStringWriterBox(from: writerRaw) {
            writer = stringWriter
        } else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_writer_write received invalid Writer handle")
        }
        guard let ptr = UnsafeMutableRawPointer(bitPattern: textRaw),
              let text = extractString(from: ptr)
        else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_writer_write received invalid text")
        }
        do {
            try writer.write(text)
        } catch let failure as RuntimeKotlinThrownError {
            throw RuntimeThrownHandle(failure.thrownRaw)
        } catch {
            throw RuntimeThrownHandle(runtimeAllocateIOException(message: error.localizedDescription))
        }
        return 0
    }
}

@_cdecl("__kk_buffered_writer_new_line")
public func __kk_buffered_writer_new_line(_ writerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_writer_new_line received invalid BufferedWriter handle")
        }
        do {
            try writer.newLine()
        } catch let failure as RuntimeKotlinThrownError {
            throw RuntimeThrownHandle(failure.thrownRaw)
        } catch {
            throw RuntimeThrownHandle(runtimeAllocateIOException(message: error.localizedDescription))
        }
        return 0
    }
}

@_cdecl("__kk_buffered_writer_flush")
public func __kk_buffered_writer_flush(_ writerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        let writer: any RuntimeJavaWriter
        if let bufferedWriter = runtimeBufferedWriterBox(from: writerRaw) {
            writer = bufferedWriter
        } else if let stringWriter = runtimeStringWriterBox(from: writerRaw) {
            writer = stringWriter
        } else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_writer_flush received invalid Writer handle")
        }
        do {
            try writer.flush()
        } catch let failure as RuntimeKotlinThrownError {
            throw RuntimeThrownHandle(failure.thrownRaw)
        } catch {
            throw RuntimeThrownHandle(runtimeAllocateIOException(message: error.localizedDescription))
        }
        return 0
    }
}


@_cdecl("__kk_writer_buffered_default")
public func __kk_writer_buffered_default(_ writerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    __kk_writer_buffered(writerRaw, 8192, outThrown)
}

@_cdecl("__kk_writer_buffered")
public func __kk_writer_buffered(_ writerRaw: Int, _ bufferSizeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard bufferSizeRaw > 0 else {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "bufferSize must be positive"))
        }
        if runtimeBufferedWriterBox(from: writerRaw) != nil {
            return writerRaw
        }
        guard let writer = runtimeStringWriterBox(from: writerRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_writer_buffered received invalid Writer handle")
        }
        return runtimeRegisterJavaWriter(
            RuntimeBufferedWriterBox(writer: writer, bufferSize: bufferSizeRaw),
            fqName: "java.io.BufferedWriter",
            parentFQName: "java.io.Writer"
        )
    }
}

@_cdecl("__kk_bytearrayinputstream_new")
public func __kk_bytearrayinputstream_new(_ bufferRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard let size = runtimeArrayBox(from: bufferRaw)?.count ?? runtimeListBox(from: bufferRaw)?.count else {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "expected ByteArray/List<Int> buffer"))
        }
        return runtimeRegisterIoStream(RuntimeInputStreamBox(arrayRaw: bufferRaw, offset: 0, length: size), fqName: "java.io.ByteArrayInputStream", input: true)
    }
}

@_cdecl("__kk_bytearray_inputStream")
public func __kk_bytearray_inputStream(_ arrayRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard let size = runtimeArrayBox(from: arrayRaw)?.count ?? runtimeListBox(from: arrayRaw)?.count else {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "expected ByteArray handle"))
        }
        return runtimeRegisterIoStream(RuntimeInputStreamBox(arrayRaw: arrayRaw, offset: 0, length: size), fqName: "java.io.ByteArrayInputStream", input: true)
    }
}

@_cdecl("__kk_bytearray_inputStream_range")
public func __kk_bytearray_inputStream_range(
    _ arrayRaw: Int,
    _ offsetRaw: Int,
    _ lengthRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard let size = runtimeArrayBox(from: arrayRaw)?.count ?? runtimeListBox(from: arrayRaw)?.count else {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "expected ByteArray handle"))
        }
        let offset = offsetRaw
        let length = lengthRaw
        guard offset >= 0, offset <= size, length >= 0, length <= size - offset else {
            throw RuntimeThrownHandle(runtimeAllocateIndexOutOfBoundsException(
                message: "offset=\(offset) length=\(length) size=\(size)"
            ))
        }
        return runtimeRegisterIoStream(RuntimeInputStreamBox(arrayRaw: arrayRaw, offset: offset, length: length), fqName: "java.io.ByteArrayInputStream", input: true)
    }
}

@_cdecl("__kk_string_byteInputStream_flat")
public func __kk_string_byteInputStream_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return runtimeStringByteInputStream(source)
}

private func runtimeStringByteInputStream(_ source: String) -> Int {
    let bytes = KotlinStringSurrogateEncoding.unicodeString(source).utf8.map { UInt8($0) }
    return runtimeRegisterIoStream(RuntimeInputStreamBox(data: Data(bytes), closeIsNoOp: true), fqName: "java.io.ByteArrayInputStream", input: true)
}

@_cdecl("__kk_input_stream_read")
public func __kk_input_stream_read(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: -1) {
        if let callback = runtimeKotlinInputStream(from: streamRaw) { return callback.read(outThrown) }
        if let sequence = runtimeSequenceInputStreamBox(from: streamRaw) { return sequence.readByte(outThrown) }
        guard let stream = runtimeInputStreamBox(from: streamRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_read received invalid InputStream handle")
        }
        let result = stream.readByte()
        runtimePropagateInputStreamError(stream, outThrown)
        return result
    }
}

@_cdecl("__kk_input_stream_available")
public func __kk_input_stream_available(_ streamRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_available received invalid InputStream handle")
    }
    return stream.available()
}

@_cdecl("__kk_input_stream_skip")
public func __kk_input_stream_skip(_ streamRaw: Int, _ countRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: -1) {
        if runtimeKotlinInputStream(from: streamRaw) != nil || runtimeSequenceInputStreamBox(from: streamRaw) != nil {
            var skipped = 0
            while skipped < max(0, countRaw) {
                let value = __kk_input_stream_read(streamRaw, outThrown)
                if let outThrown, outThrown.pointee != 0 { return skipped }
                if value == -1 { break }
                skipped += 1
            }
            return skipped
        }
        guard let stream = runtimeInputStreamBox(from: streamRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_skip received invalid InputStream handle")
        }
        let result = stream.skip(countRaw)
        runtimePropagateInputStreamError(stream, outThrown)
        return result
    }
}

@_cdecl("__kk_input_stream_read_bytes")
public func __kk_input_stream_read_bytes(_ streamRaw: Int, _ bytesRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: -1) {
        let count = runtimeArrayBox(from: bytesRaw)?.count ?? runtimeListBox(from: bytesRaw)?.count
        guard let count else {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "expected ByteArray/List<Int> buffer"))
        }
        return __kk_input_stream_read_range(streamRaw, bytesRaw, 0, count, outThrown)
    }
}

// The receiver is not closed — `InputStream.readBytes()` mirrors JVM
// `InputStream.readAllBytes()` in that the caller is responsible for closing
// the stream (typically via `.use { it.readBytes() }`).
/// All callers of readAllBytes/readBytes observe Kotlin ByteArray storage.
/// Allocate a fresh primitive array and install its declared nominal type here;
/// no element inspection or reference-component retagging is involved.
private func runtimeMakeIoReadByteArray(_ elements: [Int]) -> Int {
    let raw = runtimeMakeArrayRaw(elements)
    runtimeRegisterArrayType(rawValue: raw, typeID: runtimeStableNominalTypeID(fqName: "kotlin.ByteArray"))
    return raw
}

@_cdecl("__kk_input_stream_readAllBytes")
public func __kk_input_stream_readAllBytes(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        if runtimeKotlinInputStream(from: streamRaw) != nil {
            let array = RuntimeArrayBox(length: 8192)
            let raw = registerRuntimeObject(array)
            // The scratch buffer crosses into the Kotlin `(ByteArray, Int, Int)`
            // read callback, whose entry casts the argument to ByteArray — tag the
            // nominal type or the cast fails with ClassCastException (KUU-4298).
            runtimeRegisterArrayType(rawValue: raw, typeID: runtimeStableNominalTypeID(fqName: "kotlin.ByteArray"))
            var result: [Int] = []
            while true {
                let count = __kk_input_stream_read_range(streamRaw, raw, 0, array.count, outThrown)
                if let outThrown, outThrown.pointee != 0 { return 0 }
                if count == -1 { break }
                if count == 0 {
                    let byte = __kk_input_stream_read(streamRaw, outThrown)
                    if let outThrown, outThrown.pointee != 0 { return 0 }
                    if byte == -1 { break }
                    result.append(Int(Int8(truncatingIfNeeded: byte)))
                } else {
                    result.append(contentsOf: array.elements.prefix(count))
                }
            }
            return runtimeMakeIoReadByteArray(result)
        }
        if let stream = runtimeInputStreamBox(from: streamRaw) {
            let bytes = stream.readAllBytes()
            runtimePropagateInputStreamError(stream, outThrown)
            return runtimeMakeIoReadByteArray(bytes)
        }
        if let ptr = UnsafeMutableRawPointer(bitPattern: streamRaw),
           let sequenceStream = tryCast(ptr, to: RuntimeSequenceInputStreamBox.self)
        {
            let bytes = sequenceStream.readAllBytes(outThrown)
            return runtimeMakeIoReadByteArray(bytes)
        }
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_readAllBytes received invalid InputStream handle")
    }
}

@_cdecl("__kk_input_stream_mark")
public func __kk_input_stream_mark(_ streamRaw: Int, _ readLimitRaw: Int) -> Int {
    if runtimeKotlinInputStream(from: streamRaw) != nil || runtimeSequenceInputStreamBox(from: streamRaw) != nil { return 0 }
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_mark received invalid InputStream handle")
    }
    stream.mark()
    return 0
}

@_cdecl("__kk_input_stream_reset")
public func __kk_input_stream_reset(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        if runtimeKotlinInputStream(from: streamRaw) != nil || runtimeSequenceInputStreamBox(from: streamRaw) != nil {
            throw RuntimeThrownHandle(runtimeAllocateIOException(message: "mark/reset not supported"))
        }
        guard let stream = runtimeInputStreamBox(from: streamRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_reset received invalid InputStream handle")
        }
        if !stream.reset() {
            throw RuntimeThrownHandle(runtimeAllocateIOException(message: "mark/reset not supported"))
        }
        return 0
    }
}

@_cdecl("__kk_input_stream_mark_supported")
public func __kk_input_stream_mark_supported(_ streamRaw: Int) -> Int {
    if runtimeKotlinInputStream(from: streamRaw) != nil || runtimeSequenceInputStreamBox(from: streamRaw) != nil { return kk_box_bool(0) }
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_mark_supported received invalid InputStream handle")
    }
    return kk_box_bool(stream.markSupported() ? 1 : 0)
}

@_cdecl("__kk_input_stream_close")
public func __kk_input_stream_close(_ streamRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_close received invalid InputStream handle")
    }
    stream.close()
    return 0
}

// The InputStream is not closed after copying (matching Kotlin/JVM behaviour).
@_cdecl("__kk_input_stream_copyTo")
public func __kk_input_stream_copyTo(
    _ streamRaw: Int,
    _ outStreamRaw: Int,
    _ bufferSizeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: kk_box_long(0)) {
        guard runtimeInputStreamBox(from: streamRaw) != nil || runtimeKotlinInputStream(from: streamRaw) != nil || runtimeSequenceInputStreamBox(from: streamRaw) != nil else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_copyTo received invalid InputStream handle")
        }
        guard let outputStream = runtimeOutputStreamBox(from: outStreamRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_copyTo received invalid OutputStream handle")
        }
        let bufferSize = max(1, kk_unbox_int(bufferSizeRaw))
        var totalBytesCopied: Int = 0
        let buffer = RuntimeArrayBox(length: bufferSize)
        let rawBuffer = registerRuntimeObject(buffer)
        // The scratch buffer crosses into the Kotlin `(ByteArray, Int, Int)`
        // read callback (via `__kk_input_stream_read_range` on callback-backed
        // streams such as `Source.asInputStream()`), whose entry casts the
        // argument to ByteArray — tag the nominal type or the cast fails with
        // ClassCastException (KUU-4298).
        runtimeRegisterArrayType(rawValue: rawBuffer, typeID: runtimeStableNominalTypeID(fqName: "kotlin.ByteArray"))
        while true {
            let bytesRead = __kk_input_stream_read_range(streamRaw, rawBuffer, 0, bufferSize, outThrown)
            if let outThrown, outThrown.pointee != 0 { return kk_box_long(totalBytesCopied) }
            if bytesRead <= 0 { break }
            let chunk = Array(buffer.elements.prefix(bytesRead))
            do {
                try outputStream.writeBytes(chunk)
            } catch let error as RuntimeKotlinThrownError {
                outThrown?.pointee = error.thrownRaw
                return kk_box_long(totalBytesCopied)
            } catch {
                outThrown?.pointee = runtimeAllocateIOException(message: error.localizedDescription)
                return kk_box_long(totalBytesCopied)
            }
            totalBytesCopied += bytesRead
        }
        return kk_box_long(totalBytesCopied)
    }
}

// Since the byte-level reading methods provided by RuntimeInputStreamBox
// already operate against an in-memory Data buffer, returning the same handle
// re-typed as a BufferedInputStream preserves observable Kotlin semantics:
//   - read()/available()/skip()/close() continue to delegate to the same
//     underlying byte source
//   - mark/reset remain unsupported (mirroring FileInputStream behaviour)
//   - the buffer size argument is honoured by the type but does not alter
//     the in-memory byte sequence
@_cdecl("__kk_input_stream_buffered_default")
public func __kk_input_stream_buffered_default(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard runtimeInputStreamBox(from: streamRaw) != nil || runtimeKotlinInputStream(from: streamRaw) != nil else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_buffered_default received invalid InputStream handle")
        }
        // The underlying RuntimeInputStreamBox already buffers via Data, so we
        // can hand out the same handle re-typed.  Returning the same raw value
        // keeps reference counting consistent.
        return streamRaw
    }
}

@_cdecl("__kk_input_stream_buffered")
public func __kk_input_stream_buffered(_ streamRaw: Int, _ bufferSizeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard runtimeInputStreamBox(from: streamRaw) != nil || runtimeKotlinInputStream(from: streamRaw) != nil else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_buffered received invalid InputStream handle")
        }
        // Kotlin's reference implementation throws IllegalArgumentException for
        // non-positive buffer sizes (BufferedInputStream's underlying JVM type
        // does the same).  Surface that diagnostic via the standard outThrown
        // channel rather than returning a sentinel.
        if bufferSizeRaw <= 0 {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "Buffer size <= 0"))
        }
        return streamRaw
    }
}


private func runtimeSequenceInputStreamBox(from raw: Int) -> RuntimeSequenceInputStreamBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeSequenceInputStreamBox.self)
}

@_cdecl("__kk_sequence_input_stream_new")
public func __kk_sequence_input_stream_new(_ firstRaw: Int, _ secondRaw: Int) -> Int {
    guard runtimeInputStreamBox(from: firstRaw) != nil || runtimeKotlinInputStream(from: firstRaw) != nil || runtimeSequenceInputStreamBox(from: firstRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_input_stream_new: invalid first InputStream handle")
    }
    guard runtimeInputStreamBox(from: secondRaw) != nil || runtimeKotlinInputStream(from: secondRaw) != nil || runtimeSequenceInputStreamBox(from: secondRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_input_stream_new: invalid second InputStream handle")
    }
    return runtimeRegisterIoStream(RuntimeSequenceInputStreamBox(first: firstRaw, second: secondRaw), fqName: "java.io.SequenceInputStream", input: true)
}

@_cdecl("__kk_sequence_input_stream_read")
public func __kk_sequence_input_stream_read(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: -1) {
        guard let stream = runtimeSequenceInputStreamBox(from: streamRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_input_stream_read received invalid SequenceInputStream handle")
        }
        return stream.readByte(outThrown)
    }
}

@_cdecl("__kk_output_stream_write_byte")
public func __kk_output_stream_write_byte(_ streamRaw: Int, _ valueRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_write_byte received invalid OutputStream handle")
        }
        do {
            try stream.writeByte(valueRaw)
        } catch let kotlinThrown as RuntimeKotlinThrownError {
            throw RuntimeThrownHandle(kotlinThrown.thrownRaw)
        } catch {
            throw RuntimeThrownHandle(runtimeAllocateIOException(message: error.localizedDescription))
        }
        return 0
    }
}

@_cdecl("__kk_output_stream_write_bytes")
public func __kk_output_stream_write_bytes(_ streamRaw: Int, _ bytesRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_write_bytes received invalid OutputStream handle")
        }
        guard let bytes = runtimeByteArrayBytes(from: bytesRaw) else {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "expected ByteArray/List<Int> buffer"))
        }
        do {
            try stream.write(Data(bytes))
        } catch let kotlinThrown as RuntimeKotlinThrownError {
            throw RuntimeThrownHandle(kotlinThrown.thrownRaw)
        } catch {
            throw RuntimeThrownHandle(runtimeAllocateIOException(message: error.localizedDescription))
        }
        return 0
    }
}

@_cdecl("__kk_output_stream_flush")
public func __kk_output_stream_flush(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_flush received invalid OutputStream handle")
        }
        do {
            try stream.flush()
        } catch let kotlinThrown as RuntimeKotlinThrownError {
            throw RuntimeThrownHandle(kotlinThrown.thrownRaw)
        } catch {
            throw RuntimeThrownHandle(runtimeAllocateIOException(message: error.localizedDescription))
        }
        return 0
    }
}


/// Maps Kotlin `Charset` tag (mirrors `kotlin.text.Charsets.*` IDs in the
/// runtime ABI) to a Swift `String.Encoding`.
private func outputStreamEncoding(for charsetRaw: Int) -> String.Encoding {
    switch charsetRaw {
    case 1: .isoLatin1
    case 2: .ascii
    case 3: .utf16
    case 4: .utf16BigEndian
    case 5: .utf16LittleEndian
    case 6: .utf32
    case 7: .utf32BigEndian
    case 8: .utf32LittleEndian
    default: .utf8
    }
}

/// Subsequent writes/closes of the returned writer affect the underlying
/// stream; the original `OutputStream` handle should no longer be used directly.
@_cdecl("__kk_output_stream_bufferedWriter")
public func __kk_output_stream_bufferedWriter(_ streamRaw: Int, _ charsetRaw: Int) -> Int {
    guard let stream = runtimeOutputStreamBox(from: streamRaw), let tag = CharsetTag(rawValue: charsetRaw) else {
        fatalError("KSwiftK panic: invalid OutputStream/Charset tag")
    }
    return runtimeRegisterJavaWriter(
        RuntimeBufferedWriterBox(stream: stream, charsetTag: tag),
        fqName: "java.io.BufferedWriter",
        parentFQName: "java.io.Writer"
    )
}


/// Because the underlying `RuntimeOutputStreamBox` is already streamed through
/// the OS-level FileHandle (which performs its own buffering), the wrapped
/// handle is the receiver itself — matching Kotlin's identity contract for an
/// already-buffered stream
/// (`if (this is BufferedOutputStream) this else BufferedOutputStream(this)`).
@_cdecl("__kk_output_stream_buffered")
public func __kk_output_stream_buffered(_ streamRaw: Int) -> Int {
    guard runtimeOutputStreamBox(from: streamRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_buffered received invalid OutputStream handle")
    }
    return streamRaw
}

/// The `bufferSize` parameter is currently honored by the underlying OS-level
/// FileHandle, so this overload also returns the receiver handle. Reserved for a
/// future BufferedOutputStream-backed implementation that respects the
/// requested buffer size explicitly.
@_cdecl("__kk_output_stream_buffered_sized")
public func __kk_output_stream_buffered_sized(_ streamRaw: Int, _ bufferSize: Int) -> Int {
    _ = bufferSize // Reserved for explicit BufferedOutputStream implementation.
    guard runtimeOutputStreamBox(from: streamRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_buffered_sized received invalid OutputStream handle")
    }
    return streamRaw
}


@_cdecl("__kk_kotlin_sink_output_stream")
public func __kk_kotlin_sink_output_stream(
    _ writeFnPtr: Int,
    _ writeClosureRaw: Int,
    _ flushFnPtr: Int,
    _ flushClosureRaw: Int,
    _ closeFnPtr: Int,
    _ closeClosureRaw: Int
) -> Int {
    let sink = RuntimeKotlinOutputStreamSink(
        writeFnPtr: writeFnPtr,
        writeClosureRaw: writeClosureRaw,
        flushFnPtr: flushFnPtr,
        flushClosureRaw: flushClosureRaw,
        closeFnPtr: closeFnPtr,
        closeClosureRaw: closeClosureRaw
    )
    return runtimeRegisterIoStream(
        RuntimeOutputStreamBox(sink: sink),
        fqName: "java.io.OutputStream",
        input: false
    )
}


/// Kotlin's default buffer size for `kotlin.io.copyTo`.  Matches
/// `kotlin.io.DEFAULT_BUFFER_SIZE` (16 KiB).
private let kReaderCopyToDefaultBufferSize: Int = 16 * 1024

/// Mirrors the JVM contract:
///   - Neither the receiver nor `out` is closed by this function.
///   - A non-positive `bufferSize` raises `IllegalArgumentException` to match
///     the behaviour of `kotlin.io.copyTo` on the JVM.
///
/// `Reader` handles are any `RuntimeReaderCharSource` — reader boxes plus
/// Kotlin-source `java.io.Reader` subclasses (StringReader, user subclasses,
/// KUU-4031) — and `Writer` handles are any `RuntimeJavaWriter` (`BufferedWriter`,
/// `StringWriter`). Passing any other box panics with a clear diagnostic so
/// test failures surface immediately.
@_cdecl("__kk_reader_copyTo")
public func __kk_reader_copyTo(
    _ readerRaw: Int,
    _ writerRaw: Int,
    _ bufferSizeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: kk_box_long(0)) {
        guard let source = runtimeReaderCharSource(from: readerRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_reader_copyTo received invalid Reader handle")
        }
        guard let writer = runtimeBufferedWriterBox(from: writerRaw).map({ $0 as any RuntimeJavaWriter })
            ?? runtimeStringWriterBox(from: writerRaw).map({ $0 as any RuntimeJavaWriter }) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_reader_copyTo received invalid Writer handle")
        }

        if bufferSizeRaw <= 0 {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(
                message: "bufferSize must be positive (was \(bufferSizeRaw))"
            )
            return kk_box_long(0)
        }

        if let kotlinSource = source as? RuntimeKotlinReaderCharSource {
            // UTF-16-unit path — keeps surrogate pairs together and preserves
            // the internal lone-surrogate marker encoding a scalar loop would
            // reject (KUU-4031).
            var copied: Int = 0
            var pendingUnits: [UInt16] = []
            pendingUnits.reserveCapacity(bufferSizeRaw)

            while true {
                let unit = kotlinSource.read()
                if unit < 0 {
                    break
                }
                pendingUnits.append(UInt16(truncatingIfNeeded: unit))
                copied += 1

                if pendingUnits.count >= bufferSizeRaw {
                    do {
                        try writer.write(runtimeKotlinStringFromUTF16CodeUnits(pendingUnits))
                    } catch {
                        outThrown?.pointee = runtimeAllocateIOException(message: error.localizedDescription)
                        return kk_box_long(copied)
                    }
                    pendingUnits.removeAll(keepingCapacity: true)
                }
            }

            if !pendingUnits.isEmpty {
                do {
                    try writer.write(runtimeKotlinStringFromUTF16CodeUnits(pendingUnits))
                } catch {
                    outThrown?.pointee = runtimeAllocateIOException(message: error.localizedDescription)
                    return kk_box_long(copied)
                }
            }

            if kotlinSource.thrown != 0 {
                outThrown?.pointee = kotlinSource.thrown
            }
            return kk_box_long(copied)
        }

        var copied: Int = 0
        var pending = String.UnicodeScalarView()
        pending.reserveCapacity(bufferSizeRaw)

        while true {
            let charCode = source.read()
            if charCode < 0 {
                break
            }
            guard let scalar = Unicode.Scalar(UInt32(charCode)) else {
                // Invalid scalar — surface as IOException to match JVM-style
                // surface for malformed character data.
                outThrown?.pointee = runtimeAllocateIOException(
                    message: "invalid Unicode scalar in Reader stream (code point \(charCode))"
                )
                return kk_box_long(copied)
            }
            pending.append(scalar)
            copied += 1

            if pending.count >= bufferSizeRaw {
                do {
                    try writer.write(String(pending))
                } catch {
                    outThrown?.pointee = runtimeAllocateIOException(message: error.localizedDescription)
                    return kk_box_long(copied)
                }
                pending.removeAll(keepingCapacity: true)
            }
        }

        if !pending.isEmpty {
            do {
                try writer.write(String(pending))
            } catch {
                outThrown?.pointee = runtimeAllocateIOException(message: error.localizedDescription)
                return kk_box_long(copied)
            }
        }

        return kk_box_long(copied)
    }
}

@_cdecl("__kk_reader_copyTo_default")
public func __kk_reader_copyTo_default(
    _ readerRaw: Int,
    _ writerRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_reader_copyTo(readerRaw, writerRaw, kReaderCopyToDefaultBufferSize, outThrown)
}
