import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum JVMJDKClasspathCache {
    static func load(
        image: URL,
        jimage: URL,
        patterns: [String],
        store: ContentAddressedStore? = defaultStore(),
        extract: () throws -> [JVMJDKClasspath.ClassFile]
    ) throws -> [JVMJDKClasspath.ClassFile] {
        guard let store, let key = key(image: image, jimage: jimage, patterns: patterns) else {
            return try extract()
        }
        if let data = store.load(key: key),
           let files = try? PropertyListDecoder().decode([JVMJDKClasspath.ClassFile].self, from: data),
           key == Self.key(image: image, jimage: jimage, patterns: patterns)
        {
            return files
        }

        let files = try extract()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if key == Self.key(image: image, jimage: jimage, patterns: patterns),
           let data = try? encoder.encode(files)
        {
            store.store(key: key, payload: data)
        }
        return files
    }

    private static func defaultStore() -> ContentAddressedStore? {
        if let override = ProcessInfo.processInfo.environment["KSWIFTK_JDK_CACHE_DIR"], !override.isEmpty {
            return ContentAddressedStore(rootPath: override)
        }
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return ContentAddressedStore(rootPath: caches.appendingPathComponent("kswiftk/jvm-jdk").path)
    }

    private static func key(image: URL, jimage: URL, patterns: [String]) -> String? {
        guard let imageStamp = fileStamp(image), let toolStamp = fileStamp(jimage) else { return nil }
        return ContentAddressedStore.makeKey(parts: ["jvm-jdk-classes-v1"] + imageStamp + toolStamp + patterns)
    }

    private static func fileStamp(_ url: URL) -> [String]? {
        let path = url.resolvingSymlinksInPath().path
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            return nil
        }
        // Change time catches in-place writes even when the modification time is restored.
        #if canImport(Darwin)
        let modified = info.st_mtimespec
        let changed = info.st_ctimespec
        #else
        let modified = info.st_mtim
        let changed = info.st_ctim
        #endif
        return [
            path, String(info.st_dev), String(info.st_ino), String(info.st_size),
            String(modified.tv_sec), String(modified.tv_nsec), String(changed.tv_sec), String(changed.tv_nsec),
        ]
    }
}
