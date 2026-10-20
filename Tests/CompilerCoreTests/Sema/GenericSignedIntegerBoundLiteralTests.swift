@testable import CompilerCore
import Testing

@Suite
struct GenericSignedIntegerBoundLiteralTests {
    @Test
    func signedIntegerBoundsContextualizeConstantsAndKeepOverloadPriority() throws {
        let ctx = makeContextFromSource("""
        fun <T : Byte> byteEcho(v: T): T = v
        fun <T : Short> shortEcho(v: T): T = v
        fun <T : Long> longEcho(v: T): T = v
        fun <T : Byte?> nullableEcho(v: T): T = v
        fun <T> identity(v: T): T = v
        fun <T : UByte> ubyteEcho(v: T): T = v
        fun <T : UShort> ushortEcho(v: T): T = v
        fun pick(v: Int): Int = 1
        fun <T : Byte> pick(v: T): String = "generic"
        fun use() {
            val b: Byte = byteEcho(127)
            val min: Byte = byteEcho(-128)
            val s: Short = shortEcho(32767)
            val l: Long = longEcho(1)
            val n: Byte? = nullableEcho(1)
            val i: Int = identity(1)
            val chosen: Int = pick(1)
            val ub: UByte = ubyteEcho(1u)
            val us: UShort = ushortEcho(1u)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func signedBoundLiteralAdaptationKeepsRangeAndTypeBoundaries() throws {
        let ctx = makeContextFromSource("""
        fun <T : Byte> byteEcho(v: T): T = v
        fun <T : Short> shortEcho(v: T): T = v
        fun <T : UByte> unsignedEcho(v: T): T = v
        fun <T : Float> floatEcho(v: T): T = v
        fun badByteUpper() { byteEcho(128) }
        fun badByteLower() { byteEcho(-129) }
        fun badShort() { shortEcho(32768) }
        fun badVariable(v: Int) { byteEcho(v) }
        fun badUnsigned() { byteEcho(1u) }
        fun badLongSuffix() { byteEcho(1L) }
        fun badExplicit() { byteEcho<Int>(1) }
        fun badFloating() { floatEcho(1) }
        fun badSignedToUnsigned() { unsignedEcho(1) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.count == 9,
                "\(ctx.diagnostics.diagnostics)")
    }
}
