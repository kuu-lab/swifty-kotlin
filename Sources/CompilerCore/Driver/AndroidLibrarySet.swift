import Foundation

/// Android libraries (AARs) and plain jars that an APK or DEX build
/// consumes, unpacked into a private directory: what AGP's
/// `debugRuntimeClasspath` artifact transforms produce. Jars feed Sema
/// (lazily) and d8; AAR resources, manifests and assets feed aapt2 and the
/// manifest merger.
package final class AndroidLibrarySet {
    package struct Library {
        /// Human-readable origin for diagnostics (`group:artifact:version` or a path).
        package let origin: String
        /// Manifest `package`: the namespace of the library's `R` class.
        package let package: String?
        package let manifest: AndroidXMLElement?
        package let resources: URL?
        package let assets: URL?
        package let nativeLibraries: URL?
    }

    package let directory: URL
    package private(set) var libraries: [Library] = []
    /// Every jar in classpath order: each AAR's `classes.jar` and
    /// `libs/*.jar`, then plain jar dependencies, in dependency order.
    package private(set) var jars: [String] = []

    private init(directory: URL) {
        self.directory = directory
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// `inputs` pairs an origin label with an `.aar` or `.jar` file.
    package static func prepare(_ inputs: [(origin: String, file: URL)]) throws -> AndroidLibrarySet {
        let set = AndroidLibrarySet(directory: try AndroidBuildTool.makeWorkDirectory())
        var seenJars: Set<String> = []
        for (index, input) in inputs.enumerated() {
            let path = input.file.standardizedFileURL.path
            switch input.file.pathExtension.lowercased() {
            case "aar":
                let target = set.directory.appendingPathComponent("aar-\(index)", isDirectory: true)
                let library = try unpack(aar: input.file, origin: input.origin, into: target, jars: &set.jars)
                set.libraries.append(library)
            case "jar", "zip":
                if seenJars.insert(path).inserted { set.jars.append(path) }
            default:
                throw AndroidPackagingError.invalidInput(
                    "Android dependency \(input.origin) is neither an .aar nor a .jar: \(path)"
                )
            }
        }
        return set
    }

    private static func unpack(
        aar: URL, origin: String, into directory: URL, jars: inout [String]
    ) throws -> Library {
        let archive: ZipArchive
        do {
            archive = try ZipArchive(data: Data(contentsOf: aar))
        } catch {
            throw AndroidPackagingError.invalidInput("Cannot read Android library \(origin): \(error)")
        }
        let fileManager = FileManager.default
        var hasResources = false, hasAssets = false, hasNative = false
        var manifest: AndroidXMLElement?
        for entry in archive.entries where !entry.isDirectory {
            let name = entry.name
            // Reject absolute and parent-relative names: an AAR must not
            // write outside its extraction directory.
            guard !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else {
                throw AndroidPackagingError.invalidInput("Android library \(origin) has an unsafe entry: \(name)")
            }
            let isClasspathJar = name == "classes.jar" || (name.hasPrefix("libs/") && name.hasSuffix(".jar"))
            let isResource = name.hasPrefix("res/")
            let isAsset = name.hasPrefix("assets/")
            let isNative = name.hasPrefix("jni/") && name.hasSuffix(".so")
            guard isClasspathJar || isResource || isAsset || isNative || name == "AndroidManifest.xml" else {
                continue
            }
            let bytes = Data(try archive.contents(of: entry))
            if name == "AndroidManifest.xml" {
                do {
                    manifest = try AndroidXMLElement.parse(bytes)
                } catch {
                    throw AndroidPackagingError.invalidInput("Android library \(origin) has an invalid manifest: \(error)")
                }
                continue
            }
            let destination = directory.appendingPathComponent(name)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: destination)
            if isClasspathJar { jars.append(destination.path) }
            hasResources = hasResources || isResource
            hasAssets = hasAssets || isAsset
            hasNative = hasNative || isNative
        }
        return Library(
            origin: origin,
            package: manifest?[attribute: "package"],
            manifest: manifest,
            resources: hasResources ? directory.appendingPathComponent("res", isDirectory: true) : nil,
            assets: hasAssets ? directory.appendingPathComponent("assets", isDirectory: true) : nil,
            nativeLibraries: hasNative ? directory.appendingPathComponent("jni", isDirectory: true) : nil
        )
    }
}
