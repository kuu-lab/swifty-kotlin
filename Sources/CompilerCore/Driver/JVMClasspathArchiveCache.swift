import Foundation

/// Keeps raw classfile declarations for a batch or daemon. Each compilation
/// still builds its own ordered classpath and owns its source and Sema state.
final class JVMClasspathArchiveCache {
    private struct Entry {
        let path: String
        let data: Data
        let classes: [JVMClassInfo]
    }

    private static let maximumBytes = 64 * 1024 * 1024
    private static let maximumClasses = 32_768
    private static let maximumEntries = 8

    private let lock = NSLock()
    private var entries: [Entry] = []

    func load(path: String, data: Data, decode: () throws -> [JVMClassInfo]) rethrows -> [JVMClassInfo] {
        guard data.count <= Self.maximumBytes else { return try decode() }
        let cached = lock.withLock { () -> [JVMClassInfo]? in
            guard let index = entries.firstIndex(where: { $0.path == path && $0.data == data }) else { return nil }
            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.classes
        }
        if let cached { return cached }

        let classes = try decode()
        if classes.count <= Self.maximumClasses {
            lock.withLock {
                entries.removeAll { $0.path == path }
                entries.append(Entry(path: path, data: data, classes: classes))
                var bytes = entries.reduce(0) { $0 + $1.data.count }
                var classCount = entries.reduce(0) { $0 + $1.classes.count }
                while bytes > Self.maximumBytes || classCount > Self.maximumClasses || entries.count > Self.maximumEntries {
                    let removed = entries.removeFirst()
                    bytes -= removed.data.count
                    classCount -= removed.classes.count
                }
            }
        }
        return classes
    }
}
