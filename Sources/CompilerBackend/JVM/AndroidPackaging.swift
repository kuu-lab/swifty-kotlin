import Foundation

import CompilerCore

/// Failures from the Android SDK packaging pipeline (`--emit dex`/`apk`).
enum AndroidPackagingError: Error, CustomStringConvertible {
    /// An SDK toolchain lookup problem; carries the locator's description.
    case toolchain(String)
    /// An external build-tool invocation failed.
    case commandFailed(tool: String, detail: String)
    /// A user-supplied packaging input is missing or invalid.
    case invalidInput(String)

    var description: String {
        switch self {
        case let .toolchain(detail): detail
        case let .commandFailed(tool, detail): "\(tool) failed: \(detail)"
        case let .invalidInput(detail): detail
        }
    }
}

/// Post-processes JVM classfiles into Android artifacts using the SDK
/// build-tools: `d8` for DEX, then `aapt2`/`zip`/`zipalign`/`apksigner` for a
/// signed APK. All work happens in a private temporary directory; the final
/// artifact is moved to `options.outputPath` only after every step succeeds.
enum AndroidPackaging {
    /// `--emit dex`: classes.jar -> d8 -> ZIP archive of `classes*.dex`.
    static func emitDex(
        options: CompilerOptions,
        className: String,
        classFile: Data,
        hasMain: Bool,
        module: (String, Data)?,
        classes: [(String, Data)],
        phaseTimer: PhaseTimer?
    ) throws {
        let work = try makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: work) }

        let toolchain = try resolveToolchain(options: options)
        guard let androidJar = toolchain.androidJarPath else {
            throw AndroidPackagingError.toolchain(
                AndroidSDKError.platformNotFound("No platforms/android-*/android.jar.").description
            )
        }
        let jar = try JVMJarArchive.emit(
            className: className, classFile: classFile,
            hasMain: hasMain, module: module, classes: classes
        )
        let jarPath = work.appendingPathComponent("classes.jar").path
        try jar.write(to: URL(fileURLWithPath: jarPath))

        let dexArchive = work.appendingPathComponent("dex-output.zip").path
        try runD8(
            toolchain: toolchain, options: options, phaseTimer: phaseTimer,
            output: dexArchive,
            programInputs: [jarPath] + dexProgramInputs(options: options, androidJarPath: androidJar),
            classpathEntries: dexClasspathEntries(options: options, androidJarPath: androidJar)
        )
        try installArtifact(from: dexArchive, to: options.outputPath)
    }

    /// `--emit apk`: classes.jar -> d8 -> aapt2 link -> add dex -> zipalign
    /// -> apksigner sign.
    static func emitAPK(
        options: CompilerOptions,
        className: String,
        classFile: Data,
        hasMain: Bool,
        module: (String, Data)?,
        classes: [(String, Data)],
        phaseTimer: PhaseTimer?
    ) throws {
        let work = try makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: work) }

        let toolchain = try resolveToolchain(options: options)
        guard let aapt2 = toolchain.aapt2Path else {
            throw AndroidPackagingError.toolchain(
                AndroidSDKError.toolMissing("aapt2").description
            )
        }
        guard let apksigner = toolchain.apksignerPath else {
            throw AndroidPackagingError.toolchain(
                AndroidSDKError.toolMissing("apksigner").description
            )
        }
        guard let androidJar = toolchain.androidJarPath else {
            throw AndroidPackagingError.toolchain(
                AndroidSDKError.platformNotFound("No platforms/android-*/android.jar.").description
            )
        }

        // 1. DEX the program jar plus every classpath jar into a directory.
        let jar = try JVMJarArchive.emit(
            className: className, classFile: classFile,
            hasMain: hasMain, module: module, classes: classes
        )
        let jarPath = work.appendingPathComponent("classes.jar").path
        try jar.write(to: URL(fileURLWithPath: jarPath))

        let dexDirectory = work.appendingPathComponent("dex", isDirectory: true)
        try FileManager.default.createDirectory(at: dexDirectory, withIntermediateDirectories: true)
        try runD8(
            toolchain: toolchain, options: options, phaseTimer: phaseTimer,
            output: dexDirectory.path,
            programInputs: [jarPath] + dexProgramInputs(options: options, androidJarPath: androidJar),
            classpathEntries: dexClasspathEntries(options: options, androidJarPath: androidJar)
        )
        let dexFiles = try dexFileNames(in: dexDirectory)
        guard !dexFiles.isEmpty else {
            throw AndroidPackagingError.invalidInput("d8 produced no classes*.dex output.")
        }

        // 2. aapt2 link produces the unsigned APK skeleton.
        let manifest = try resolveManifest(options: options)
        let unsignedAPK = work.appendingPathComponent("unsigned.apk").path
        var linkArguments = ["link", "-o", unsignedAPK, "-I", androidJar,
                             "--manifest", manifest]
        if let minAPI = options.android.minAPI {
            linkArguments.append("--min-sdk-version")
            linkArguments.append(String(minAPI))
        }
        if let assets = options.android.assetPath {
            linkArguments.append("-A")
            linkArguments.append(assets)
        }
        if let resources = options.android.resourcePath {
            let resURL = URL(fileURLWithPath: resources).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                throw AndroidPackagingError.invalidInput(
                    "--android-res must be a resource directory: \(resources)"
                )
            }
            let resArchive = work.appendingPathComponent("res.zip").path
            _ = try runTool(
                tool: "aapt2", executable: aapt2,
                arguments: ["compile", "--dir", resURL.path, "-o", resArchive],
                phaseTimer: phaseTimer, subPhaseName: "Android/aapt2-compile"
            )
            linkArguments.append(resArchive)
        }
        _ = try runTool(
            tool: "aapt2", executable: aapt2,
            arguments: linkArguments,
            phaseTimer: phaseTimer, subPhaseName: "Android/aapt2-link"
        )

        // 3. Add the dex files at the APK root, stored uncompressed so the
        // runtime can map them directly.
        let zip = CommandRunner.resolveExecutable("zip", fallback: "/usr/bin/zip")
        _ = try runTool(
            tool: "zip", executable: zip,
            arguments: ["-q", "-0", unsignedAPK] + dexFiles,
            currentDirectoryPath: dexDirectory.path,
            phaseTimer: phaseTimer, subPhaseName: "Android/add-dex"
        )

        // 4. Align, then sign.
        var alignedAPK = unsignedAPK
        if let zipalign = toolchain.zipalignPath {
            alignedAPK = work.appendingPathComponent("aligned.apk").path
            _ = try runTool(
                tool: "zipalign", executable: zipalign,
                arguments: ["-f", "-p", "4", unsignedAPK, alignedAPK],
                phaseTimer: phaseTimer, subPhaseName: "Android/zipalign"
            )
        }
        let signedAPK = work.appendingPathComponent("app.apk").path
        let signing = try signingArguments(options: options, phaseTimer: phaseTimer)
        // apksigner stops parsing options at the first positional argument,
        // so every flag must precede the input APK.
        _ = try runTool(
            tool: "apksigner", executable: apksigner,
            arguments: ["sign"] + signing + ["--out", signedAPK, alignedAPK],
            phaseTimer: phaseTimer, subPhaseName: "Android/apksigner"
        )
        try installArtifact(from: signedAPK, to: options.outputPath)
    }

    // MARK: - Toolchain

    private static func resolveToolchain(options: CompilerOptions) throws -> AndroidToolchain {
        do {
            return try AndroidSDKLocator.locate(
                sdkPath: options.android.sdkPath,
                buildToolsVersion: options.android.buildToolsVersion,
                compileSdk: options.android.compileSdk
            )
        } catch let error as AndroidSDKError {
            throw AndroidPackagingError.toolchain(error.description)
        }
    }

    // MARK: - d8

    /// Classpath entries that become d8 program inputs (jars/zips are dexed
    /// into the artifact). The framework `android.jar` is excluded: it is
    /// already the `--lib` bootclasspath and must never be dexed.
    private static func dexProgramInputs(options: CompilerOptions, androidJarPath: String?) -> [String] {
        let androidJar = androidJarPath.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }
        return options.jvmClasspath.compactMap { entry in
            let standardized = URL(fileURLWithPath: entry).standardizedFileURL
            if standardized.path == androidJar { return nil }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else { return nil }
            return standardized.path
        }
    }

    /// Classpath entries that only resolve symbols for d8 (directories).
    private static func dexClasspathEntries(options: CompilerOptions, androidJarPath: String?) -> [String] {
        let androidJar = androidJarPath.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }
        return options.jvmClasspath.compactMap { entry in
            let standardized = URL(fileURLWithPath: entry).standardizedFileURL
            if standardized.path == androidJar { return nil }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return nil }
            return standardized.path
        }
    }

    private static func runD8(
        toolchain: AndroidToolchain,
        options: CompilerOptions,
        phaseTimer: PhaseTimer?,
        output: String,
        programInputs: [String],
        classpathEntries: [String]
    ) throws {
        var arguments = ["--lib"]
        if let androidJar = toolchain.androidJarPath {
            arguments.append(androidJar)
        }
        if let minAPI = options.android.minAPI {
            arguments.append("--min-api")
            arguments.append(String(minAPI))
        }
        arguments.append("--output")
        arguments.append(output)
        for entry in classpathEntries {
            arguments.append("--classpath")
            arguments.append(entry)
        }
        arguments.append(contentsOf: programInputs)
        _ = try runTool(
            tool: "d8", executable: toolchain.d8Path,
            arguments: arguments,
            phaseTimer: phaseTimer, subPhaseName: "Android/d8"
        )
    }

    private static func dexFileNames(in directory: URL) throws -> [String] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("classes") && $0.hasSuffix(".dex") }
            .sorted()
        return names
    }

    // MARK: - APK packaging

    /// Manifest lookup: explicit `--manifest`, then the conventional
    /// Gradle-style locations relative to the working directory.
    private static func resolveManifest(options: CompilerOptions) throws -> String {
        if let explicit = options.android.manifestPath {
            guard FileManager.default.fileExists(atPath: explicit) else {
                throw AndroidPackagingError.invalidInput(
                    "--manifest does not exist: \(explicit)"
                )
            }
            return explicit
        }
        for candidate in [
            "AndroidManifest.xml",
            "app/src/main/AndroidManifest.xml",
            "src/main/AndroidManifest.xml",
        ] where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        throw AndroidPackagingError.invalidInput(
            "AndroidManifest.xml not found; pass --manifest <path>."
        )
    }

    /// apksigner arguments for the resolved keystore. The default debug
    /// keystore at `~/.android/debug.keystore` is generated via `keytool`
    /// when absent, matching Gradle's debug-signing behaviour.
    private static func signingArguments(
        options: CompilerOptions,
        phaseTimer: PhaseTimer?
    ) throws -> [String] {
        let android = options.android
        let keystore = android.keystorePath
            ?? NSHomeDirectory() + "/.android/debug.keystore"
        let alias = android.keyAlias ?? "androiddebugkey"
        let storePassword = android.storePassword ?? "android"
        let keyPassword = android.keyPassword ?? storePassword
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: keystore) {
            guard android.keystorePath == nil else {
                throw AndroidPackagingError.invalidInput(
                    "--android-keystore does not exist: \(keystore)"
                )
            }
            try generateDebugKeystore(
                path: keystore, alias: alias,
                storePassword: storePassword, keyPassword: keyPassword,
                phaseTimer: phaseTimer
            )
        }
        return [
            "--ks", keystore,
            "--ks-key-alias", alias,
            "--ks-pass", "pass:\(storePassword)",
            "--key-pass", "pass:\(keyPassword)",
        ]
    }

    private static func generateDebugKeystore(
        path: String,
        alias: String,
        storePassword: String,
        keyPassword: String,
        phaseTimer: PhaseTimer?
    ) throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keytool = CommandRunner.resolveExecutable("keytool", fallback: "/usr/bin/keytool")
        _ = try runTool(
            tool: "keytool", executable: keytool,
            arguments: [
                "-genkeypair", "-keystore", path, "-storepass", storePassword,
                "-keypass", keyPassword, "-alias", alias,
                "-keyalg", "RSA", "-keysize", "2048", "-validity", "10950",
                "-dname", "CN=Android Debug,O=Android,C=US",
            ],
            phaseTimer: phaseTimer, subPhaseName: "Android/keytool"
        )
    }

    // MARK: - Process helpers

    private static func runTool(
        tool: String,
        executable: String,
        arguments: [String],
        currentDirectoryPath: String? = nil,
        phaseTimer: PhaseTimer?,
        subPhaseName: String
    ) throws -> CommandResult {
        do {
            return try CommandRunner.run(
                executable: executable, arguments: arguments,
                currentDirectoryPath: currentDirectoryPath,
                phaseTimer: phaseTimer, subPhaseName: subPhaseName,
                timeout: 600
            )
        } catch let error as CommandRunnerError {
            throw AndroidPackagingError.commandFailed(tool: tool, detail: describe(error))
        } catch {
            throw AndroidPackagingError.commandFailed(tool: tool, detail: String(describing: error))
        }
    }

    private static func describe(_ error: CommandRunnerError) -> String {
        switch error {
        case let .launchFailed(reason):
            return "failed to launch: \(reason)"
        case let .nonZeroExit(result):
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            var output = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            if output.count > 4_000 { output = String(output.prefix(4_000)) + "…" }
            return "exit \(result.exitCode)\(output.isEmpty ? "" : ": \(output)")"
        case let .timedOut(reason):
            return "timed out: \(reason)"
        }
    }

    private static func makeWorkDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-android-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Moves the finished artifact into place, replacing any previous output.
    /// The parent directory is created when missing.
    private static func installArtifact(from source: String, to destination: String) throws {
        let fileManager = FileManager.default
        let destinationURL = URL(fileURLWithPath: destination).standardizedFileURL
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        do {
            try fileManager.moveItem(atPath: source, toPath: destinationURL.path)
        } catch {
            try fileManager.copyItem(atPath: source, toPath: destinationURL.path)
        }
    }
}
