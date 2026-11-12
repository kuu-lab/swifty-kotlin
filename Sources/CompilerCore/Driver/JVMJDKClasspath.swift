import Foundation

/// Materializes the imported packages from the active JDK runtime image as
/// lazy classpath entries. The JVM class reader consumes ordinary class files;
/// `jimage` is the JDK-supported way to expose them from `lib/modules`.
struct JVMJDKClasspath {
    struct ClassFile: Codable {
        let path: String
        let contents: Data
    }

    let classFiles: [ClassFile]
    let requiredLazyClassNames: Set<String>

    static func prepare(for ctx: CompilationContext) throws -> JVMJDKClasspath {
        guard let javaHome = locateJavaHome() else { return empty }
        let image = javaHome.appendingPathComponent("lib/modules")
        let jimage = javaHome.appendingPathComponent("bin/jimage")
        guard FileManager.default.fileExists(atPath: image.path),
              FileManager.default.isExecutableFile(atPath: jimage.path)
        else { return empty }

        var packages: Set<String> = ["java/lang"]
        var recursivePackages: Set<String> = []
        var requiredLazyClassNames: Set<String> = []
        for file in ctx.sourceManager.fileIDs()
        where ctx.sourceManager.origin(of: file) == .user
            && !ctx.sourceManager.path(of: file).hasPrefix("<kswiftk-jvm>/")
        {
            let source = String(decoding: ctx.sourceManager.contents(of: file), as: UTF8.self)
            for path in importedPaths(in: source) {
                if path == "kotlin.io.path" || path.hasPrefix("kotlin.io.path.") || path == "kotlin.io.Path" {
                    recursivePackages.insert("java/nio")
                    requiredLazyClassNames.insert("java/nio/file/Path")
                    continue
                }
                let importedPackages = packagePaths(for: path)
                packages.formUnion(importedPackages)
                if importedPackages.contains("java/time") {
                    recursivePackages.insert("java/time")
                }
                if importedPackages.contains("java/nio") {
                    recursivePackages.insert("java/nio")
                }
                if importedPackages.contains("java/util/concurrent") {
                    recursivePackages.insert("java/util/concurrent")
                }
            }
        }

        var patterns = packages.sorted().map { "glob:**/\($0)/*.class" }
            + recursivePackages.sorted().map { "glob:**/\($0)/**/*.class" }
        // These two signatures complete JDK interface hierarchies commonly
        // reached from java.lang.Iterable and java.nio.file.DirectoryStream.
        patterns += ["glob:**/java/util/Iterator.class", "glob:**/java/io/Closeable.class"]
        let classFiles = try JVMJDKClasspathCache.load(image: image, jimage: jimage, patterns: patterns) {
            try extractClasses(image: image, jimage: jimage, patterns: patterns)
        }
        return JVMJDKClasspath(classFiles: classFiles, requiredLazyClassNames: requiredLazyClassNames)
    }

    private static func extractClasses(image: URL, jimage: URL, patterns: [String]) throws -> [ClassFile] {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-jvm-jdk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let process = Process()
        process.executableURL = jimage
        process.arguments = ["extract", "--include", patterns.joined(separator: ","), "--dir", temporaryRoot.path, image.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw JVMFrontendError(message: "Cannot run JDK jimage: \(error)")
        }
        let errorText = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw JVMFrontendError(message: "Cannot extract JDK classes from \(image.path): \(errorText)")
        }

        let moduleDirectories = try FileManager.default.contentsOfDirectory(
            at: temporaryRoot, includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var classFiles: [ClassFile] = []
        for module in moduleDirectories {
            try JVMClasspathIndex.forEachClassFile(inDirectory: module) { file, path in
                classFiles.append(ClassFile(path: path, contents: try Data(contentsOf: file)))
            }
        }
        return classFiles
    }

    private static var empty: JVMJDKClasspath {
        JVMJDKClasspath(classFiles: [], requiredLazyClassNames: [])
    }

    private static func importedPaths(in source: String) -> Set<String> {
        let range = NSRange(source.startIndex..., in: source)
        var paths: Set<String> = []
        let importPattern = try! NSRegularExpression(
            pattern: #"(?m)^[ \t]*import[ \t]+([A-Za-z_][A-Za-z0-9_.]*(?:\.\*)?)(?:[ \t]+as[ \t]+[A-Za-z_][A-Za-z0-9_]*)?[ \t]*(?://.*)?$"#
        )
        for match in importPattern.matches(in: source, range: range) {
            if let matchRange = Range(match.range(at: 1), in: source) {
                paths.insert(String(source[matchRange]))
            }
        }

        let packagePattern = try! NSRegularExpression(
            pattern: #"(?m)^[ \t]*package[ \t]+([A-Za-z_][A-Za-z0-9_.]*)"#
        )
        for match in packagePattern.matches(in: source, range: range) {
            if let matchRange = Range(match.range(at: 1), in: source) {
                paths.insert(String(source[matchRange]))
            }
        }

        let qualifiedNamePattern = try! NSRegularExpression(
            pattern: #"\b(?:java|javax)\.[A-Za-z_][A-Za-z0-9_.]*"#
        )
        for match in qualifiedNamePattern.matches(in: source, range: range) {
            if let matchRange = Range(match.range, in: source) {
                paths.insert(String(source[matchRange]))
            }
        }
        let kotlinPathPattern = try! NSRegularExpression(
            pattern: #"\bkotlin\.io\.path(?:\.[A-Za-z_][A-Za-z0-9_]*|\.\*)|\bkotlin\.io\.Path\b"#
        )
        for match in kotlinPathPattern.matches(in: source, range: range) {
            if let matchRange = Range(match.range, in: source) {
                paths.insert(String(source[matchRange]))
            }
        }
        return paths
    }

    static func usesKotlinPath(in source: String) -> Bool {
        importedPaths(in: source).contains {
            $0 == "kotlin.io.path" || $0.hasPrefix("kotlin.io.path.") || $0 == "kotlin.io.Path"
        }
    }

    private static func packagePaths(for path: String) -> Set<String> {
        let isStarImport = path.hasSuffix(".*")
        var components = path
            .replacingOccurrences(of: "`", with: "")
            .split(separator: ".")
            .map(String.init)
        guard components.count >= 2 else { return [] }
        if isStarImport {
            components.removeLast()
            let typeIndex = components.indices.dropFirst(2).first {
                guard let first = components[$0].first else { return false }
                return first.isUppercase
            }
            let packageEnd = typeIndex ?? components.count
            guard packageEnd >= 2 else { return [] }
            return [components.prefix(packageEnd).joined(separator: "/")]
        }

        let firstType = components.indices.dropFirst(2).first {
            guard let first = components[$0].first else { return false }
            return first.isUppercase
        }
        let packageEnd = firstType ?? (components.count - 1)
        guard packageEnd >= 2 else { return [] }
        return [components.prefix(packageEnd).joined(separator: "/")]
    }

    private static func locateJavaHome() -> URL? {
        let fileManager = FileManager.default
        if let configured = ProcessInfo.processInfo.environment["JAVA_HOME"], !configured.isEmpty {
            let home = URL(fileURLWithPath: configured).standardizedFileURL
            if fileManager.fileExists(atPath: home.appendingPathComponent("lib/modules").path) {
                return home
            }
        }

        for path in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let java = URL(fileURLWithPath: String(path)).appendingPathComponent("java")
            guard fileManager.isExecutableFile(atPath: java.path) else { continue }
            let resolved = java.resolvingSymlinksInPath().standardizedFileURL
            let home = resolved.deletingLastPathComponent().deletingLastPathComponent()
            if fileManager.fileExists(atPath: home.appendingPathComponent("lib/modules").path) {
                return home
            }
        }

        return nil
    }
}
