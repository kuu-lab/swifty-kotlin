@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {

    @Test
    func testAtomicReferenceGenericThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import kotlin.concurrent.AtomicReference

        fun main() {
            val reference = AtomicReference("source-plus-residual")
            val loaded: String = reference.get()
            println(loaded)
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "AtomicReferenceArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "source-plus-residual\n")
        }
    }

    @Test
    func testBundledAtomicPropertySetterSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        @file:Suppress("DEPRECATION_ERROR")
        import kotlin.native.concurrent.AtomicInt
        import kotlin.native.concurrent.AtomicLong
        fun main() {
            val i = AtomicInt(1)
            i.value = 42
            println(i.value)
            val l = AtomicLong(10)
            l.value = 64
            println(l.value)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "AtomicPropertySetterArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "42\n64\n")
        }
    }

    @Test(arguments: [false, true])
    func testBundledAtomicExtensionPropertyCompoundAssign(fromSource: Bool) throws {
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let source = """
        @file:Suppress("DEPRECATION_ERROR")
        import kotlin.native.concurrent.AtomicInt
        fun main() {
            val i = AtomicInt(10)
            i.value += 5
            println(i.value)
            println(i.value++)
            println(++i.value)
            println(i.value--)
            println(--i.value)
            i.value -= 3
            i.value *= 2
            i.value /= 4
            i.value %= 4
            println(i.value)
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "AtomicPropertyCompoundAssign",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: fromSource,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "15\n15\n17\n17\n15\n2\n")
        }
    }
}
