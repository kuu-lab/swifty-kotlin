@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {

    /// KUU-4487: calling `toString()` through an abstract/sealed receiver
    /// whose static type does not itself override `toString` returned null.
    /// The static layout has no source override in the slot, so the call
    /// used the raw ABI while the dynamic class registered its flat-ABI
    /// override. The slot now always stores `kk_any_member_to_string` and
    /// dispatches through the Any-toString registry.
    @Test
    func testAbstractReceiverToStringVirtualCallUsesUniformRawSlotABI() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        sealed class Base
        class ImplA(val v: Int) : Base() {
            override fun toString() = "A$v"
        }
        class ImplNoOverride(val v: Int) : Base()

        abstract class Abs
        class ImplD(val v: Int) : Abs() {
            override fun toString() = "D$v"
        }

        abstract class A3
        data class DC(val v: Int) : A3()

        open class WithToString {
            override fun toString() = "W"
        }
        data class DC2(val v: Int) : WithToString()

        fun main() {
            val a: Base = ImplA(1)
            println(a.toString())
            val b: Base = ImplNoOverride(2)
            println(b.toString().startsWith("ImplNoOverride@"))
            val d: Abs = ImplD(3)
            println(d.toString())
            val x: A3 = DC(9)
            println(x.toString())
            val y: WithToString = DC2(8)
            println(y.toString())
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }

            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "KUU4487AbstractReceiverToStringArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                    == "A1\ntrue\nD3\nDC(v=9)\nDC2(v=8)\n"
            )
        }
    }
}
