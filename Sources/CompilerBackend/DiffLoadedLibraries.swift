import CompilerCore
import Foundation

#if canImport(Darwin)
import MachO
#endif

/// Identifies loaded libraries whose changes can affect the compiler.
/// On Darwin the sealed system libraries are covered by the OS version.
enum DiffLoadedLibraries {
    static func current(excluding executable: String) -> [(String, String)]? {
        let paths: [String]
        #if canImport(Darwin)
        paths = (0..<_dyld_image_count()).compactMap { index in
            _dyld_get_image_name(index).map { String(cString: $0) }
        }
        #elseif os(Linux)
        guard let maps = try? String(contentsOfFile: "/proc/self/maps", encoding: .utf8) else { return nil }
        paths = linuxMappedPaths(maps)
        #else
        return nil
        #endif
        let excluded = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
        var unique: Set<String> = []
        for path in paths {
            guard path.hasPrefix("/") else { return nil }
            guard !path.hasSuffix(" (deleted)") else { return nil }
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            if resolved == excluded { continue }
            #if canImport(Darwin)
            if isSystemLibrary(resolved) { continue }
            #endif
            unique.insert(resolved)
        }
        var identities: [(String, String)] = []
        for path in unique.sorted() {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]) else {
                return nil
            }
            identities.append((path, FileFingerprint.compute(for: path, contents: data).contentHash))
        }
        return identities
    }

    static func isSystemLibrary(_ path: String) -> Bool {
        path.hasPrefix("/System/") || path.hasPrefix("/usr/lib/") || path.hasPrefix("/lib/") || path.hasPrefix("/lib64/")
    }

    static func linuxMappedPaths(_ maps: String) -> [String] {
        maps.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 5, whereSeparator: { $0 == " " || $0 == "\t" })
            // Executable mappings identify loaded code rather than unrelated
            // mapped data, which can change during an artifact build.
            guard fields.count == 6, fields[1].contains("x"), fields[5].hasPrefix("/") else { return nil }
            return String(fields[5])
        }
    }
}
