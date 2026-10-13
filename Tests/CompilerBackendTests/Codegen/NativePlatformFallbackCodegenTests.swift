#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct NativePlatformFallbackCodegenTests {
    @Test(arguments: [0, 2])
    func emptyNoStdlibProgramEmitsValidLLVMAndObject(optimization: Int) throws {
        try withTemporaryFile(contents: "fun main() {}\n") { path in
            for emit in [EmitMode.llvmIR, .object] {
                let outputPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent("no-stdlib-empty-\(UUID().uuidString)").path
                defer {
                    try? FileManager.default.removeItem(atPath: outputPath)
                    try? FileManager.default.removeItem(atPath: outputPath + ".ll")
                    try? FileManager.default.removeItem(atPath: outputPath + ".o")
                }
                let context = makeContext(
                    path: path, outputPath: outputPath, emit: emit,
                    optimization: optimization, mode: "none"
                )
                try runToKIR(context)
                try LoweringPhase().run(context)
                let kir = try #require(context.kir)
                let bridgeNames: Set<String> = [
                    "kk_platform_canAccessUnaligned", "kk_platform_isLittleEndian",
                    "kk_platform_osFamily", "kk_platform_cpuArchitecture", "kk_platform_memoryModel",
                ]
                var seen = Set<String>()
                for declaration in kir.arena.declarations {
                    guard case let .function(function) = declaration else { continue }
                    for instruction in function.body {
                        guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                              bridgeNames.contains(context.interner.resolve(callee)) else { continue }
                        seen.insert(context.interner.resolve(callee))
                        #expect(arguments.count == 1, "Platform bridges require their singleton receiver")
                    }
                }
                #expect(seen == bridgeNames)
                try CodegenPhase().run(context)
                #expect(!context.diagnostics.hasError)
            }
        }
    }

    @Test(arguments: [0, 2], ["none", "source", "artifact"])
    func platformPropertiesExecuteWithEachStdlibMode(optimization: Int, mode: String) throws {
        let headers = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.Platform
        import kotlin.native.Platform.isLittleEndian
        import kotlin.native.OsFamily
        import kotlin.native.CpuArchitecture
        import kotlin.native.MemoryModel
        """
        let body: String
        if mode == "none" {
            body = """
            fun main() {
                val platform = Platform
                val unaligned = Platform.canAccessUnaligned
                val little = isLittleEndian
                val family = kotlin.native.Platform.osFamily
                val architecture = platform.cpuArchitecture
                val memory = Platform.memoryModel
                val processors = Platform.getAvailableProcessors()
            }
            """
        } else {
            body = """
            fun main() {
                val platform = Platform
                println(Platform.canAccessUnaligned)
                println(isLittleEndian)
                println(kotlin.native.Platform.osFamily == OsFamily.UNKNOWN)
                println(platform.cpuArchitecture == CpuArchitecture.UNKNOWN)
                println(Platform.memoryModel == MemoryModel.EXPERIMENTAL)
                println(Platform.getAvailableProcessors() > 0)
            }
            """
        }
        try withTemporaryFile(contents: headers + "\n" + body) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("platform-stdlib-mode-\(UUID().uuidString)").path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let context = makeContext(
                path: path, outputPath: outputPath, emit: .executable,
                optimization: optimization, mode: mode,
                stdlibPath: mode == "artifact" ? try testStdlibArtifactPath() : nil
            )
            try runToKIR(context)
            let userFile = try #require(context.sourceManager.fileID(forPath: path))
            let userErrors = context.diagnostics.diagnostics.filter {
                $0.severity == .error && $0.primaryRange?.start.file == userFile
            }
            #expect(userErrors.isEmpty)
            try LoweringPhase().run(context)
            try CodegenPhase().run(context)
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
#if arch(arm64) || arch(x86_64)
            let expected = mode == "none" ? "" : "true\ntrue\nfalse\nfalse\ntrue\ntrue\n"
            #expect(result.stdout == expected)
#else
            Issue.record("Add host expectations for this architecture")
#endif
        }
    }

    private func makeContext(
        path: String, outputPath: String, emit: EmitMode,
        optimization: Int, mode: String, stdlibPath: String? = nil
    ) -> CompilationContext {
        CompilationContext(
            options: CompilerOptions(
                moduleName: "NativePlatformFallback", inputs: [path], outputPath: outputPath,
                emit: emit, target: defaultTargetTriple(),
                optLevel: optimization == 0 ? .O0 : .O2,
                includeStdlib: mode != "none", stdlibLibraryPath: stdlibPath,
                allowDefaultStdlibLibrary: false
            ),
            sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner()
        )
    }
}
#endif
