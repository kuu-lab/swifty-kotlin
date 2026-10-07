@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct NarrowRotationExecutionTests {
    @Test(arguments: [true, false])
    func testNarrowRotations(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun probe(b: Byte, s: Short, ub: UByte, us: UShort, count: Int) {
                println(b.rotateLeft(count))
                println(b.rotateRight(count))
                println(s.rotateLeft(count))
                println(s.rotateRight(count))
                println(ub.rotateLeft(count))
                println(ub.rotateRight(count))
                println(us.rotateLeft(count))
                println(us.rotateRight(count))
            }
            fun main() {
                probe((-128).toByte(), (-32768).toShort(), 128.toUByte(), 32768.toUShort(), 1)
                probe((-127).toByte(), (-32767).toShort(), 129.toUByte(), 32769.toUShort(), -1)
                probe(1.toByte(), 1.toShort(), 1.toUByte(), 1.toUShort(), 17)
                probe((-1).toByte(), (-1).toShort(), 255.toUByte(), 65535.toUShort(), Int.MAX_VALUE)
                probe(1.toByte(), 1.toShort(), 1.toUByte(), 1.toUShort(), Int.MIN_VALUE)
            }
            """,
            expectedOutput: """
            1
            64
            1
            16384
            1
            64
            1
            16384
            -64
            3
            -16384
            3
            192
            3
            49152
            3
            2
            -128
            2
            -32768
            2
            128
            2
            32768
            -1
            -1
            -1
            -1
            255
            255
            65535
            65535
            1
            1
            1
            1
            1
            1
            1
            1

            """,
            moduleName: "KUU1277NarrowRotations",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
