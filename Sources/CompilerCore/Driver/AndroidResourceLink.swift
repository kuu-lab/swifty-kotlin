import Foundation

package enum AndroidPackagingError: Error, CustomStringConvertible {
    case toolchain(String)
    case commandFailed(tool: String, detail: String)
    case invalidInput(String)

    package var description: String {
        switch self {
        case let .toolchain(detail), let .invalidInput(detail): detail
        case let .commandFailed(tool, detail): "\(tool) failed: \(detail)"
        }
    }
}

/// Owns the output of aapt2 until APK packaging finishes. The resource
/// classfiles and the unsigned APK come from the same link invocation.
package final class AndroidResourceLink {
    package let toolchain: AndroidToolchain
    package let androidJarPath: String
    package let directory: URL
    package var unsignedAPK: String { directory.appendingPathComponent("unsigned.apk").path }
    /// The app's own `R` classes, visible to Sema.
    private(set) var classFiles: [(String, Data)] = []
    /// `R` classes of library packages. Library bytecode reads them at
    /// runtime, so they are dexed, but Kotlin sources never see them.
    package private(set) var libraryClassFiles: [(String, Data)] = []

    private init(toolchain: AndroidToolchain, androidJarPath: String, directory: URL) {
        self.toolchain = toolchain
        self.androidJarPath = androidJarPath
        self.directory = directory
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    package static func prepare(
        options: AndroidOptions, toolchain: AndroidToolchain,
        libraries: AndroidLibrarySet? = nil, phaseTimer: PhaseTimer?
    ) throws -> AndroidResourceLink {
        guard let aapt2 = toolchain.aapt2Path else {
            throw AndroidPackagingError.toolchain(AndroidSDKError.toolMissing("aapt2").description)
        }
        guard let androidJar = toolchain.androidJarPath else {
            throw AndroidPackagingError.toolchain(
                AndroidSDKError.platformNotFound("No platforms/android-*/android.jar.").description
            )
        }
        do {
            let link = AndroidResourceLink(
                toolchain: toolchain, androidJarPath: androidJar,
                directory: try AndroidBuildTool.makeWorkDirectory()
            )
            try link.run(aapt2: aapt2, options: options, libraries: libraries, phaseTimer: phaseTimer)
            return link
        } catch let error as AndroidPackagingError {
            throw error
        } catch {
            throw AndroidPackagingError.invalidInput("Cannot prepare Android resources: \(error)")
        }
    }

    private func run(
        aapt2: String, options: AndroidOptions, libraries: AndroidLibrarySet?, phaseTimer: PhaseTimer?
    ) throws {
        let (manifest, appPackage) = try prepareManifest(options: options, libraries: libraries)
        var arguments = ["link", "-o", unsignedAPK, "-I", androidJarPath, "--manifest", manifest]
        if let minAPI = options.minAPI {
            arguments += ["--min-sdk-version", String(minAPI)]
        }
        if let targetSdk = options.targetSdk {
            arguments += ["--target-sdk-version", String(targetSdk)]
        }
        if let versionCode = options.versionCode {
            arguments += ["--version-code", String(versionCode)]
        }
        if let versionName = options.versionName {
            arguments += ["--version-name", versionName]
        }
        if options.debuggable {
            arguments.append("--debug-mode")
        }
        if let applicationID = options.applicationID, applicationID != appPackage {
            // The manifest package stays the R namespace; aapt2 rewrites the
            // package and expands relative component names against the old one.
            arguments += ["--rename-manifest-package", applicationID]
        }
        if let assets = options.assetPath {
            arguments += ["-A", assets]
        }
        let resourceLibraries = (libraries?.libraries ?? []).compactMap { library in
            library.resources.map { (package: library.package, resources: $0) }
        }
        for library in libraries?.libraries ?? [] {
            if let assets = library.assets { arguments += ["-A", assets.path] }
        }
        var generatesR = false
        if !resourceLibraries.isEmpty {
            // Overlays apply in order, later winning: dependencies before the
            // libraries that depend on them (the resolver lists dependents
            // first), and the app's own resources last.
            for (index, library) in resourceLibraries.enumerated().reversed() {
                let archive = directory.appendingPathComponent("library-res-\(index).zip").path
                try AndroidBuildTool.run(
                    tool: "aapt2", executable: aapt2,
                    arguments: ["compile", "--dir", library.resources.path, "-o", archive],
                    phaseTimer: phaseTimer, subPhaseName: "Android/aapt2-compile"
                )
                arguments += ["-R", archive]
            }
            arguments.append("--auto-add-overlay")
            let packages = Set(resourceLibraries.compactMap { $0.package }).subtracting([appPackage]).sorted()
            if !packages.isEmpty {
                arguments += ["--extra-packages", packages.joined(separator: ":")]
            }
            generatesR = true
        }
        if let resources = options.resourcePath {
            let resURL = URL(fileURLWithPath: resources).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw AndroidPackagingError.invalidInput(
                    "--android-res must be a resource directory: \(resources)"
                )
            }
            let resArchive = directory.appendingPathComponent("res.zip").path
            try AndroidBuildTool.run(
                tool: "aapt2", executable: aapt2,
                arguments: ["compile", "--dir", resURL.path, "-o", resArchive],
                phaseTimer: phaseTimer, subPhaseName: "Android/aapt2-compile"
            )
            // With library overlays the app's resources must overlay last so
            // they override library values; alone they are the base input.
            arguments += resourceLibraries.isEmpty ? [resArchive] : ["-R", resArchive]
            generatesR = true
        }
        let javaSources = directory.appendingPathComponent("java", isDirectory: true)
        if generatesR {
            try FileManager.default.createDirectory(at: javaSources, withIntermediateDirectories: true)
            arguments += ["--java", javaSources.path]
        }
        try AndroidBuildTool.run(
            tool: "aapt2", executable: aapt2, arguments: arguments,
            phaseTimer: phaseTimer, subPhaseName: "Android/aapt2-link"
        )
        if generatesR {
            let appDirectory = appPackage.replacingOccurrences(of: ".", with: "/") + "/"
            let compiled = try compileResourceClasses(phaseTimer: phaseTimer)
            classFiles = compiled.filter { $0.0.hasPrefix(appDirectory) && !$0.0.dropFirst(appDirectory.count).contains("/") }
            libraryClassFiles = compiled.filter { entry in !classFiles.contains { $0.0 == entry.0 } }
        }
    }

    /// The manifest aapt2 links: the app manifest as given, or merged with
    /// the library manifests (written into the work directory).
    private func prepareManifest(
        options: AndroidOptions, libraries: AndroidLibrarySet?
    ) throws -> (path: String, package: String) {
        let path = try Self.resolveManifest(options.manifestPath)
        let app: AndroidXMLElement
        do {
            app = try AndroidXMLElement.parse(Data(contentsOf: URL(fileURLWithPath: path)))
        } catch {
            throw AndroidPackagingError.invalidInput("Cannot read \(path): \(error)")
        }
        guard let package = app[attribute: "package"] ?? options.namespace else {
            throw AndroidPackagingError.invalidInput(
                "\(path) has no package attribute; pass --android-namespace <package>."
            )
        }
        let manifests = (libraries?.libraries ?? []).compactMap { library in
            library.manifest.map { (package: library.package, manifest: $0) }
        }
        // Merge even without libraries: `${applicationId}` placeholders and
        // `tools:` markers in the app manifest itself must be processed.
        let merged = AndroidManifestMerger.merge(
            app: app, namespace: package,
            applicationID: options.applicationID ?? package,
            libraries: manifests
        )
        let output = directory.appendingPathComponent("AndroidManifest.xml")
        try Data(merged.serialized().utf8).write(to: output)
        return (output.path, package)
    }

    private func compileResourceClasses(phaseTimer: PhaseTimer?) throws -> [(String, Data)] {
        let sources = directory.appendingPathComponent("java", isDirectory: true)
        let inputs = try Self.files(in: sources, withExtension: "java")
        guard !inputs.isEmpty else { return [] }
        let output = directory.appendingPathComponent("resource-classes", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let javaHomeJavac = ProcessInfo.processInfo.environment["JAVA_HOME"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("bin/javac").path }
        let javac = javaHomeJavac.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
            ?? CommandRunner.resolveExecutable("javac", fallback: "/usr/bin/javac")
        try AndroidBuildTool.run(
            tool: "javac", executable: javac,
            arguments: ["--release", "8", "-proc:none", "-encoding", "UTF-8", "-d", output.path] + inputs.map(\.path),
            phaseTimer: phaseTimer, subPhaseName: "Android/javac"
        )
        let base = output.resolvingSymlinksInPath()
        return try Self.files(in: base, withExtension: "class").map { file in
            let name = file.resolvingSymlinksInPath().pathComponents
                .dropFirst(base.pathComponents.count).joined(separator: "/")
            return (name, try Data(contentsOf: file))
        }
    }

    private static func files(in directory: URL, withExtension suffix: String) throws -> [URL] {
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw AndroidPackagingError.invalidInput("Cannot read directory: \(directory.path)")
        }
        return files.compactMap { $0 as? URL }.filter { $0.pathExtension == suffix }.sorted { $0.path < $1.path }
    }

    private static func resolveManifest(_ explicit: String?) throws -> String {
        if let explicit {
            guard FileManager.default.fileExists(atPath: explicit) else {
                throw AndroidPackagingError.invalidInput("--manifest does not exist: \(explicit)")
            }
            return explicit
        }
        for candidate in ["AndroidManifest.xml", "app/src/main/AndroidManifest.xml", "src/main/AndroidManifest.xml"]
            where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        throw AndroidPackagingError.invalidInput("AndroidManifest.xml not found; pass --manifest <path>.")
    }
}
