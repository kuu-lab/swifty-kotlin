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
    private(set) var classFiles: [(String, Data)] = []

    private init(toolchain: AndroidToolchain, androidJarPath: String, directory: URL) {
        self.toolchain = toolchain
        self.androidJarPath = androidJarPath
        self.directory = directory
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    package static func prepare(
        options: AndroidOptions, toolchain: AndroidToolchain, phaseTimer: PhaseTimer?
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
            try link.run(aapt2: aapt2, options: options, phaseTimer: phaseTimer)
            return link
        } catch let error as AndroidPackagingError {
            throw error
        } catch {
            throw AndroidPackagingError.invalidInput("Cannot prepare Android resources: \(error)")
        }
    }

    private func run(aapt2: String, options: AndroidOptions, phaseTimer: PhaseTimer?) throws {
        let manifest = try Self.resolveManifest(options.manifestPath)
        var arguments = ["link", "-o", unsignedAPK, "-I", androidJarPath, "--manifest", manifest]
        if let minAPI = options.minAPI {
            arguments += ["--min-sdk-version", String(minAPI)]
        }
        if let assets = options.assetPath {
            arguments += ["-A", assets]
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
            let javaSources = directory.appendingPathComponent("java", isDirectory: true)
            try FileManager.default.createDirectory(at: javaSources, withIntermediateDirectories: true)
            arguments += ["--java", javaSources.path, resArchive]
        }
        try AndroidBuildTool.run(
            tool: "aapt2", executable: aapt2, arguments: arguments,
            phaseTimer: phaseTimer, subPhaseName: "Android/aapt2-link"
        )
        if options.resourcePath != nil {
            classFiles = try compileResourceClasses(phaseTimer: phaseTimer)
        }
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
