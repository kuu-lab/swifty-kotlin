#if os(macOS)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func foundationPointersKeepTheirTypeAcrossErasure(fromArtifact: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
            import kotlinx.cinterop.*
            import kotlinx.io.bytestring.*
            import platform.Foundation.*

            fun <T> erasedIdentity(value: T): T = value

            fun main() {
                val data = ByteString(byteArrayOf(1, 2, 3)).toNSData()
                val pointer = erasedIdentity(data.bytes!!)
                println(pointer.readBytes(data.length.toInt()).joinToString())
                println(data.toByteString().toByteArray().joinToString())
            }
            """,
            expectedOutput: "1, 2, 3\n1, 2, 3\n",
            moduleName: "FoundationPointerTypes",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
#endif
