#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct IndexedNumericArrayIncrementTests {
    @Test
    func indexedLongAndDoubleCompoundAssignmentsAcceptIntLiterals() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val longs = mutableListOf(0L, 0L, 0L)
            longs[1] += 5
            val doubles = mutableListOf(0.0, 0.0)
            doubles[1] += 5
        }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func explicitIndexedCompoundAssignmentStillChecksRightHandType() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val values = byteArrayOf(1)
            values[0] += 1L
        }
        """)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test
    func indexedSmallIntegerArrayIncrementAndDecrementTypecheck() throws {
        let ctx = makeContextFromSource("""
        @OptIn(ExperimentalUnsignedTypes::class)
        fun main() {
            val boxedBytes: Array<Byte> = arrayOf<Byte>(1)
            boxedBytes[0]++
            boxedBytes[0]--
            val bytes = byteArrayOf(127, -128)
            bytes[0]++
            bytes[1]--
            val boxedShorts: Array<Short> = arrayOf<Short>(1)
            boxedShorts[0]++
            boxedShorts[0]--
            val shorts = shortArrayOf(32767, -32768)
            shorts[0]++
            shorts[1]--
            val ubytes = ubyteArrayOf(255u, 0u)
            ubytes[0]++
            ubytes[1]--
            val ushorts = ushortArrayOf(65535u, 0u)
            ushorts[0]++
            ushorts[1]--
        }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func indexedSmallIntegerListAndCustomGetSetIncrementAndDecrementTypecheck() throws {
        let ctx = makeContextFromSource("""
        class ByteCell(var value: Byte) {
            operator fun get(index: Int): Byte = value
            operator fun set(index: Int, next: Byte) { value = next }
        }

        fun use(list: ArrayList<Short>, byteCell: ByteCell) {
            list[0]++
            list[0]--
            byteCell[0]++
            byteCell[0]--
        }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func indexedSmallIntegerGenericGetSetIncrementAndDecrementTypecheck() throws {
        let ctx = makeContextFromSource("""
        class GenericCell<T>(var value: T) {
            operator fun get(index: Int): T = value
            operator fun set(index: Int, next: T) { value = next }
        }

        fun use(genericByte: GenericCell<Byte>, genericShort: GenericCell<Short>) {
            genericByte[0]++
            genericByte[0]--
            genericShort[0]++
            genericShort[0]--
        }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
