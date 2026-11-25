import Foundation

/// Inputs of a `--emit dex|apk` build beyond the Kotlin sources and
/// `--classpath`: Maven dependencies, local libraries and Java sources.
/// Prepared before Sema because Kotlin code compiles against all of them.
package final class AndroidBuildInputs {
    /// Builds the Kotlin/JVM runtime jar for `-include-runtime`. The runtime
    /// is compiled by the JVM backend, which installs this hook; Java
    /// sources need it on the `javac` classpath when they use `kotlin.*`.
    nonisolated(unsafe) package static var runtimeJarProvider: ((CompilerOptions) throws -> Data)?

    package let libraries: AndroidLibrarySet?
    package let javaClassesJar: String?
    private let directory: URL?

    /// Jars d8 packages in addition to `--classpath` jars.
    package var dexJars: [String] { (libraries?.jars ?? []) + [javaClassesJar].compactMap { $0 } }

    private init(libraries: AndroidLibrarySet?, javaClassesJar: String?, directory: URL?) {
        self.libraries = libraries
        self.javaClassesJar = javaClassesJar
        self.directory = directory
    }

    deinit {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    /// Resolves `--android-dependency` and unpacks every library input.
    package static func resolveLibraries(_ options: AndroidOptions) throws -> AndroidLibrarySet? {
        guard options.hasLibraryInputs else { return nil }
        var inputs: [(origin: String, file: URL)] = []
        if !options.dependencies.isEmpty {
            let roots = try options.dependencies.map { text in
                guard let coordinate = MavenCoordinate(parsing: text) else {
                    throw MavenResolutionError.invalidCoordinate(text)
                }
                return coordinate
            }
            let repositories = MavenRepositorySet(
                repositories: options.mavenRepositories,
                cacheDirectory: options.mavenCachePath ?? MavenRepositorySet.defaultCacheDirectory,
                offline: options.offline
            )
            for artifact in try MavenDependencyResolver(repositories: repositories).resolve(roots) {
                inputs.append((artifact.coordinate.description, artifact.file))
            }
        }
        for path in options.libraries {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw AndroidPackagingError.invalidInput("--android-library does not exist: \(path)")
            }
            inputs.append((path, url))
        }
        return try AndroidLibrarySet.prepare(inputs)
    }

    package static func prepare(
        options: CompilerOptions,
        androidJarPath: String,
        libraries: AndroidLibrarySet?,
        resourceClassFiles: [(String, Data)],
        phaseTimer: PhaseTimer?
    ) throws -> AndroidBuildInputs {
        let sources = options.android.javaSources
        guard !sources.isEmpty else {
            return AndroidBuildInputs(libraries: libraries, javaClassesJar: nil, directory: nil)
        }
        let directory = try AndroidBuildTool.makeWorkDirectory()
        let inputs = AndroidBuildInputs(libraries: libraries, javaClassesJar: directory.appendingPathComponent("java-classes.jar").path, directory: directory)
        var classpath = [androidJarPath] + options.jvmClasspath + (libraries?.jars ?? [])
        if !resourceClassFiles.isEmpty {
            let resources = directory.appendingPathComponent("r-classes", isDirectory: true)
            for (name, bytes) in resourceClassFiles {
                let file = resources.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: file)
            }
            classpath.append(resources.path)
        }
        if options.includeJVMRuntime {
            guard let provider = runtimeJarProvider else {
                throw AndroidPackagingError.toolchain("-include-runtime with Java sources needs the JVM backend's runtime provider.")
            }
            let runtime = directory.appendingPathComponent("kotlin-runtime.jar")
            try provider(options).write(to: runtime)
            classpath.append(runtime.path)
        }
        for source in sources where !FileManager.default.fileExists(atPath: source) {
            throw AndroidPackagingError.invalidInput("Java source does not exist: \(source)")
        }
        let output = directory.appendingPathComponent("java-classes", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try AndroidBuildTool.run(
            tool: "javac", executable: javacPath(),
            arguments: ["--release", "8", "-proc:none", "-encoding", "UTF-8", "-nowarn",
                        "-cp", classpath.joined(separator: ":"), "-d", output.path] + sources,
            phaseTimer: phaseTimer, subPhaseName: "Android/javac-sources"
        )
        let zip = CommandRunner.resolveExecutable("zip", fallback: "/usr/bin/zip")
        try AndroidBuildTool.run(
            tool: "zip", executable: zip,
            arguments: ["-q", "-r", inputs.javaClassesJar!, "."],
            currentDirectoryPath: output.path,
            phaseTimer: phaseTimer, subPhaseName: "Android/java-classes-jar"
        )
        return inputs
    }

    package static func javacPath() -> String {
        let javaHomeJavac = ProcessInfo.processInfo.environment["JAVA_HOME"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("bin/javac").path }
        return javaHomeJavac.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
            ?? CommandRunner.resolveExecutable("javac", fallback: "/usr/bin/javac")
    }
}
