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
            let classFile = try JVMClassFile.emit(program, target: ctx.options.jvmTarget, javaParameters: ctx.options.javaParameters)
            var classes = try program.classes.map { type in
                (type.name + ".class", try JVMClassFile.emit(type, program: program, target: ctx.options.jvmTarget, javaParameters: ctx.options.javaParameters))
            }
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
            let module = JVMMetadata.module(program)
            let modulePath = "META-INF/" + program.moduleName + ".kotlin_module"
            let output = URL(fileURLWithPath: ctx.options.outputPath)
            switch ctx.options.emit {
            case .jvmJar:
                let archive = try JVMJarArchive.emit(className: program.internalClassName, classFile: classFile, hasMain: program.hasMain, module: (modulePath, module), classes: classes)
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
                        module: (modulePath, module), classes: dexClasses,
                        phaseTimer: ctx.phaseTimer
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
}
