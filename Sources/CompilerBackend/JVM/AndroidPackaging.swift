import Foundation

import CompilerCore

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
        inputs: AndroidBuildInputs?,
        phaseTimer: PhaseTimer?
    ) throws {
        let work = try AndroidBuildTool.makeWorkDirectory()
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
            programInputs: [jarPath] + dexProgramInputs(options: options, androidJarPath: androidJar)
                + (inputs?.dexJars ?? []),
            classpathEntries: dexClasspathEntries(options: options, androidJarPath: androidJar)
        )
        try installArtifact(from: dexArchive, to: options.outputPath)
    }

    /// `--emit apk`: add the program's dex files to the aapt2-linked APK,
    /// align it and sign it.
    static func emitAPK(
        options: CompilerOptions,
        className: String,
        classFile: Data,
        hasMain: Bool,
        module: (String, Data)?,
        classes: [(String, Data)],
        linkedResources: AndroidResourceLink?,
        inputs: AndroidBuildInputs?,
        phaseTimer: PhaseTimer?
    ) throws {
        let toolchain = try linkedResources?.toolchain ?? resolveToolchain(options: options)
        guard let apksigner = toolchain.apksignerPath else {
            throw AndroidPackagingError.toolchain(
                AndroidSDKError.toolMissing("apksigner").description
            )
        }
        let resources = try linkedResources ?? AndroidResourceLink.prepare(
            options: options.android, toolchain: toolchain, phaseTimer: phaseTimer
        )
        let androidJar = resources.androidJarPath
        let work = resources.directory

        // 1. DEX the program jar plus every classpath jar into a directory.
        let jar = try JVMJarArchive.emit(
            className: className, classFile: classFile,
            hasMain: hasMain, module: module, classes: classes
        )
        let jarPath = work.appendingPathComponent("classes.jar").path
        try jar.write(to: URL(fileURLWithPath: jarPath))

        let dexDirectory = work.appendingPathComponent("dex", isDirectory: true)
        try FileManager.default.createDirectory(at: dexDirectory, withIntermediateDirectories: true)
        let programInputs = [jarPath] + dexProgramInputs(options: options, androidJarPath: androidJar)
            + (inputs?.dexJars ?? [])
        try runD8(
            toolchain: toolchain, options: options, phaseTimer: phaseTimer,
            output: dexDirectory.path,
            programInputs: programInputs,
            classpathEntries: dexClasspathEntries(options: options, androidJarPath: androidJar)
        )
        let dexFiles = try dexFileNames(in: dexDirectory)
        guard !dexFiles.isEmpty else {
            throw AndroidPackagingError.invalidInput("d8 produced no classes*.dex output.")
        }

        // 2. Add the dex files at the APK root, stored uncompressed so the
        // runtime can map them directly.
        let unsignedAPK = resources.unsignedAPK
        let zip = CommandRunner.resolveExecutable("zip", fallback: "/usr/bin/zip")
        try AndroidBuildTool.run(
            tool: "zip", executable: zip,
            arguments: ["-q", "-0", unsignedAPK] + dexFiles,
            currentDirectoryPath: dexDirectory.path,
            phaseTimer: phaseTimer, subPhaseName: "Android/add-dex"
        )

        // d8 keeps only classes; ServiceLoader registrations such as
        // kotlinx.coroutines' Main dispatcher live in jar resources.
        let staging = work.appendingPathComponent("apk-extra", isDirectory: true)
        let javaResources = try stageJavaResources(from: programInputs, into: staging)
        if !javaResources.isEmpty {
            try AndroidBuildTool.run(
                tool: "zip", executable: zip,
                arguments: ["-q", unsignedAPK] + javaResources,
                currentDirectoryPath: staging.path,
                phaseTimer: phaseTimer, subPhaseName: "Android/add-resources"
            )
        }
        // Native libraries are stored uncompressed (`zipalign -p` then page-aligns
        // them) so `android:extractNativeLibs="false"` can map them in place.
        let nativeLibraries = try stageNativeLibraries(inputs?.libraries, into: staging)
        if !nativeLibraries.isEmpty {
            try AndroidBuildTool.run(
                tool: "zip", executable: zip,
                arguments: ["-q", "-0", unsignedAPK] + nativeLibraries,
                currentDirectoryPath: staging.path,
                phaseTimer: phaseTimer, subPhaseName: "Android/add-native-libraries"
            )
        }

        // 3. Align, then sign.
        var alignedAPK = unsignedAPK
        if let zipalign = toolchain.zipalignPath {
            alignedAPK = work.appendingPathComponent("aligned.apk").path
            try AndroidBuildTool.run(
                tool: "zipalign", executable: zipalign,
                arguments: ["-f", "-p", "4", unsignedAPK, alignedAPK],
                phaseTimer: phaseTimer, subPhaseName: "Android/zipalign"
            )
        }
        let signedAPK = work.appendingPathComponent("app.apk").path
        let signing = try signingArguments(options: options, phaseTimer: phaseTimer)
        // apksigner stops parsing options at the first positional argument,
        // so every flag must precede the input APK.
        try AndroidBuildTool.run(
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
        try AndroidBuildTool.run(
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

    /// Copies the non-class entries of every dexed jar into `directory`,
    /// first occurrence winning, minus the entries AGP's default
    /// `packaging.resources.excludes` drop (licenses, signatures, Maven and
    /// Kotlin module metadata). Returns the relative paths written.
    static func stageJavaResources(from jars: [String], into directory: URL) throws -> [String] {
        var written: [String] = []
        var seen: Set<String> = []
        for jar in jars {
            let archive: ZipArchive
            do {
                archive = try ZipArchive(data: Data(contentsOf: URL(fileURLWithPath: jar)))
            } catch {
                throw AndroidPackagingError.invalidInput("Cannot read \(jar): \(error)")
            }
            for entry in archive.entries where !entry.isDirectory && isPackagedJavaResource(entry.name) {
                guard seen.insert(entry.name).inserted else { continue }
                let destination = directory.appendingPathComponent(entry.name)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Data(archive.contents(of: entry)).write(to: destination)
                written.append(entry.name)
            }
        }
        return written
    }

    static func isPackagedJavaResource(_ name: String) -> Bool {
        if name.hasSuffix(".class") || name.hasPrefix("/") || name.split(separator: "/").contains("..") {
            return false
        }
        let components = name.split(separator: "/")
        if components.contains(where: { $0.hasPrefix(".") || $0.hasPrefix("_") || $0.hasSuffix("~") }) {
            return false
        }
        let upper = name.uppercased()
        let root = ["LICENSE", "LICENSE.TXT", "NOTICE", "NOTICE.TXT"]
        if components.count == 1 { return !root.contains(upper) }
        guard components[0] == "META-INF" else { return true }
        if components.count == 2 {
            let file = upper.dropFirst("META-INF/".count)
            if root.contains(String(file)) || file == "MANIFEST.MF" || file == "INDEX.LIST" { return false }
            for suffix in [".SF", ".RSA", ".DSA", ".EC", ".KOTLIN_MODULE"] where file.hasSuffix(suffix) {
                return false
            }
            return true
        }
        return !["maven", "proguard", "com.android.tools", "versions"].contains(String(components[1]))
    }

    /// AAR `jni/<abi>/*.so` files become `lib/<abi>/*.so` in the APK.
    private static func stageNativeLibraries(_ libraries: AndroidLibrarySet?, into directory: URL) throws -> [String] {
        var written: [String] = []
        let fileManager = FileManager.default
        for library in libraries?.libraries ?? [] {
            guard let jni = library.nativeLibraries,
                  let files = fileManager.enumerator(at: jni, includingPropertiesForKeys: nil) else { continue }
            let base = jni.resolvingSymlinksInPath().pathComponents.count
            for case let file as URL in files where file.pathExtension == "so" {
                let relative = "lib/" + file.resolvingSymlinksInPath().pathComponents.dropFirst(base).joined(separator: "/")
                guard !written.contains(relative) else { continue }
                let destination = directory.appendingPathComponent(relative)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: file, to: destination)
                written.append(relative)
            }
        }
        return written
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
        try AndroidBuildTool.run(
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
