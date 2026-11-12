import Foundation
import CompilerCore

final class JVMCodegenPhase: CompilerPhase {
    static let name = "JVMCodegen"

    func run(_ ctx: CompilationContext) throws {
        guard let program = ctx.jvmProgram else {
            ctx.diagnostics.error("KSWIFTK-JVM-0002", "Checked JVM program is not available for codegen.", range: nil)
            throw CompilerPipelineError.outputUnavailable
        }
        do {
            // Validate and construct all bytes before touching the destination.
            let target = ctx.options.jvmTarget
            let classIndex = JVMClassFile.ClassIndex(program)
            let classFile = try JVMClassFile.emit(program, target: target, javaParameters: ctx.options.javaParameters, classIndex: classIndex)
            let runtime = ctx.options.emit == .jvmJar && ctx.options.includeJVMRuntime && !ctx.options.stdlibOnly
                ? try runtimeEntries(for: ctx.options)
                : []
            let runtimePaths = Set(runtime.map(\.0))
            let applicationClasses = program.classes.filter { type in
                !type.isRuntimeFallback || !runtimePaths.contains(type.name + ".class")
            }
            var classes = try emitClasses(applicationClasses, in: program, target: target, javaParameters: ctx.options.javaParameters, classIndex: classIndex)
            if ctx.options.stdlibOnly {
                let coverage = try JVMStdlibCoverage.report(program, classFiles: [(program.internalClassName + ".class", classFile)] + classes)
                classes.append(("META-INF/kswiftk-stdlib-coverage.json", coverage))
                classes += JVMBuiltins.resources()
                let sources = ctx.sourceManager.fileIDs().filter { ctx.sourceManager.origin(of: $0) == .user }.map { file in
                    let path = ctx.sourceManager.path(of: file)
                    return path.components(separatedBy: "/Stdlib/").last ?? path
                }.sorted().joined(separator: "\n") + "\n"
                classes.append(("META-INF/kswiftk-stdlib-sources.list", Data(sources.utf8)))
            }
            let (modulePath, module) = moduleEntry(for: program)
            let output = URL(fileURLWithPath: ctx.options.outputPath)
            switch ctx.options.emit {
            case .jvmJar:
                let archive = try JVMJarArchive.emit(
                    className: program.internalClassName, classFile: classFile, hasMain: program.hasMain,
                    module: (modulePath, module), classes: classes + runtime
                )
                try archive.write(to: output, options: .atomic)
            case .jvmClass:
                for (name, bytes) in [(program.internalClassName + ".class", classFile)] + classes {
                    let classURL = output.appendingPathComponent(name)
                    try FileManager.default.createDirectory(at: classURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try bytes.write(to: classURL, options: .atomic)
                }
                let moduleURL = output.appendingPathComponent(modulePath)
                try FileManager.default.createDirectory(at: moduleURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try module.write(to: moduleURL, options: .atomic)
            case .dex, .apk:
                // Classpath stubs (<kswiftk-jvm-import>) are compile-time
                // contracts for Sema only. Dexing them would shadow the real
                // android.jar/JDK implementations at runtime; their JVM
                // signatures still bind calls to the framework methods.
                let stubClassFiles = ctx.jvmImportedClassFileNames
                let dexClasses = classes.filter { !stubClassFiles.contains($0.0) }
                if ctx.options.emit == .dex {
                    try AndroidPackaging.emitDex(
                        options: ctx.options, className: program.internalClassName,
                        classFile: classFile, hasMain: program.hasMain,
                        module: (modulePath, module), classes: dexClasses,
                        phaseTimer: ctx.phaseTimer
                    )
                } else {
                    try AndroidPackaging.emitAPK(
                        options: ctx.options, className: program.internalClassName,
                        classFile: classFile, hasMain: program.hasMain,
                        module: (modulePath, module), classes: dexClasses + ctx.androidResourceClassFiles,
                        linkedResources: ctx.androidResourceLink, phaseTimer: ctx.phaseTimer
                    )
                }
            default:
                break
            }
        } catch let error as AndroidSDKError {
            ctx.diagnostics.error("KSWIFTK-ANDROID-0001", error.description, range: nil)
            throw CompilerPipelineError.outputUnavailable
        } catch let error as AndroidPackagingError {
            ctx.diagnostics.error("KSWIFTK-ANDROID-0002", error.description, range: nil)
            throw CompilerPipelineError.outputUnavailable
        } catch {
            ctx.diagnostics.error("KSWIFTK-JVM-0002", "Cannot emit JVM output: \(error)", range: nil)
            throw CompilerPipelineError.outputUnavailable
        }
    }

    private func runtimeEntries(for application: CompilerOptions) throws -> [(String, Data)] {
        let moduleName = application.moduleName == "KSwiftKStdlib" ? "KSwiftKStdlibRuntime" : "KSwiftKStdlib"
        guard let compiler = Self.compilerFingerprint,
              let sources = try? JVMStdlibCatalog.runtimeSourceFingerprint(),
              let store = Self.runtimeStore()
        else {
            return try buildRuntimeEntries(for: application, moduleName: moduleName)
        }
        let platform = application.target
        let key = ContentAddressedStore.makeKey(parts: [
            "jvm-runtime-v1", compiler, sources, moduleName, application.jvmTarget.rawValue,
            platform.arch, platform.vendor, platform.os, platform.osVersion ?? "",
        ])
        if let data = store.load(key: key),
           let entries = try? PropertyListDecoder().decode([RuntimeEntry].self, from: data)
        {
            return entries.map { ($0.name, $0.bytes) }
        }

        let entries = try buildRuntimeEntries(for: application, moduleName: moduleName)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if (try? JVMStdlibCatalog.runtimeSourceFingerprint()) == sources,
           let data = try? encoder.encode(entries.map { RuntimeEntry(name: $0.0, bytes: $0.1) })
        {
            store.store(key: key, payload: data)
        }
        return entries
    }

    private struct RuntimeEntry: Codable {
        let name: String
        let bytes: Data
    }

    private static let compilerFingerprint = Bundle.main.executableURL.flatMap {
        FileFingerprint.compute(for: $0.resolvingSymlinksInPath().path)?.contentHash
    }

    private static func runtimeStore() -> ContentAddressedStore? {
        if let override = ProcessInfo.processInfo.environment["KSWIFTK_JVM_RUNTIME_CACHE_DIR"], !override.isEmpty {
            return ContentAddressedStore(rootPath: override)
        }
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return ContentAddressedStore(rootPath: caches.appendingPathComponent("kswiftk/jvm-runtime").path)
    }

    private func buildRuntimeEntries(for application: CompilerOptions, moduleName: String) throws -> [(String, Data)] {
        let options = CompilerOptions(
            moduleName: moduleName, inputs: [], outputPath: application.outputPath, emit: .jvmJar,
            target: application.target, stdlibOnly: true, jvmTarget: application.jvmTarget
        )
        let result = CompilerDriver().runFrontend(options: options)
        guard !result.context.diagnostics.hasError, let program = result.context.jvmProgram else {
            let errors = result.diagnostics.filter { $0.severity == .error }
            let message = errors.map { "\($0.code): \($0.message)" }.joined(separator: "\n")
            throw JVMEmissionError.runtimeBuildFailed(message.isEmpty ? "No JVM program was generated." : message)
        }
        let classIndex = JVMClassFile.ClassIndex(program)
        let classFile = try JVMClassFile.emit(program, target: options.jvmTarget, classIndex: classIndex)
        let classes = try emitClasses(program.classes, in: program, target: options.jvmTarget, classIndex: classIndex)
        return [(program.internalClassName + ".class", classFile)] + classes
            + JVMBuiltins.resources() + [moduleEntry(for: program)]
    }

    private func emitClasses(
        _ classes: [JVMClass], in program: JVMProgram, target: JVMTarget, javaParameters: Bool = false,
        classIndex: JVMClassFile.ClassIndex
    ) throws -> [(String, Data)] {
        try classes.map { type in
            (type.name + ".class", try JVMClassFile.emit(type, program: program, target: target, javaParameters: javaParameters, classIndex: classIndex))
        }
    }

    private func moduleEntry(for program: JVMProgram) -> (String, Data) {
        ("META-INF/" + program.moduleName + ".kotlin_module", JVMMetadata.module(program))
    }
}
