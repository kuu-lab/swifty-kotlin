#if os(macOS)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func pinnedBytePointerUsesConcretePointeeType(fromArtifact: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
            import kotlinx.cinterop.*

            fun ByteArray.implicitFirst(): Byte = usePinned { it.addressOf(0)[0] }
            fun <T> identity(value: T): T = value

            fun main() {
                val bytes = byteArrayOf(-1, 0, 65)
                println(bytes.implicitFirst())
                bytes.usePinned {
                    println(it.addressOf(2)[0])
                    println(it.addressOf(1).pointed.value)
                }
                println(bytes.usePinned { 1.toByte() })
                println(identity((-1).toByte()))
                try {
                    bytes.usePinned { it.addressOf(3)[0] }
                } catch (e: IndexOutOfBoundsException) {
                    println("bounds")
                }
            }
            """,
            expectedOutput: "-1\n65\n0\n1\n-1\nbounds\n",
            moduleName: "ByteVarPointeeType",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
#endif
