#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite(.serialized)
struct CollectionPrimitiveArrayConversionTests {
    @Test
    func listAndArrayLiteralsResolvePrimitiveConversions() throws {
        let source = """
        fun main() {
            val listBooleans = listOf(true, false).toBooleanArray()
            val listBytes = listOf(1.toByte(), 2.toByte()).toByteArray()
            val listChars = listOf('a', 'b').toCharArray()
            val listDoubles = listOf(1.5, 2.5).toDoubleArray()
            val listFloats = listOf(1.0f, 2.0f).toFloatArray()
            val listInts = listOf(1, 2).toIntArray()
            val listLongs = listOf(1L, 2L).toLongArray()
            val listShorts = listOf(1.toShort(), 2.toShort()).toShortArray()

            val arrayBooleans = arrayOf(true, false).toBooleanArray()
            val arrayBytes = arrayOf(1.toByte(), 2.toByte()).toByteArray()
            val arrayChars = arrayOf('a', 'b').toCharArray()
            val arrayDoubles = arrayOf(1.5, 2.5).toDoubleArray()
            val arrayFloats = arrayOf(1.0f, 2.0f).toFloatArray()
            val arrayInts = arrayOf(1, 2).toIntArray()
            val arrayLongs = arrayOf(1L, 2L).toLongArray()
            val arrayShorts = arrayOf(1.toShort(), 2.toShort()).toShortArray()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
