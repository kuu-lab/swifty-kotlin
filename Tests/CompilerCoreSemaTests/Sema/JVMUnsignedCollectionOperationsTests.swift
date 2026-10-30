#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct JVMUnsignedCollectionOperationsTests {
    @Test
    func unsignedComparableCollectionsAndArrayAggregatesResolve() throws {
        let source = """
        fun issueRepro() {
            println(listOf(3u, 1u, 2u).sorted())
            println(uintArrayOf(3u, 1u).max())
        }

        fun issueListRepro(): List<UInt> = listOf(3u, 1u, 2u).sorted()
        fun issueArrayRepro(): UInt = uintArrayOf(3u, 1u).max()

        fun sortedUByteList(values: List<UByte>): List<UByte> = values.sorted()
        fun sortedUShortList(values: List<UShort>): List<UShort> = values.sorted()
        fun sortedUIntList(values: List<UInt>): List<UInt> = values.sorted()
        fun sortedULongList(values: List<ULong>): List<ULong> = values.sorted()

        fun sortedUByteArray(values: UByteArray): List<UByte> = values.sorted()
        fun sortedDescendingUByteArray(values: UByteArray): List<UByte> = values.sortedDescending()
        fun sortedCopyUByteArray(values: UByteArray): UByteArray = values.sortedArray()
        fun sortedDescendingCopyUByteArray(values: UByteArray): UByteArray = values.sortedArrayDescending()
        fun searchUByteArray(values: UByteArray, value: UByte): Int = values.binarySearch(value)
        fun sortedUShortArray(values: UShortArray): List<UShort> = values.sorted()
        fun sortedDescendingUShortArray(values: UShortArray): List<UShort> = values.sortedDescending()
        fun sortedCopyUShortArray(values: UShortArray): UShortArray = values.sortedArray()
        fun sortedDescendingCopyUShortArray(values: UShortArray): UShortArray = values.sortedArrayDescending()
        fun searchUShortArray(values: UShortArray, value: UShort): Int = values.binarySearch(value)
        fun sortedUIntArray(values: UIntArray): List<UInt> = values.sorted()
        fun sortedDescendingUIntArray(values: UIntArray): List<UInt> = values.sortedDescending()
        fun sortedCopyUIntArray(values: UIntArray): UIntArray = values.sortedArray()
        fun sortedDescendingCopyUIntArray(values: UIntArray): UIntArray = values.sortedArrayDescending()
        fun searchUIntArray(values: UIntArray, value: UInt): Int = values.binarySearch(value)
        fun sortedULongArray(values: ULongArray): List<ULong> = values.sorted()
        fun sortedDescendingULongArray(values: ULongArray): List<ULong> = values.sortedDescending()
        fun sortedCopyULongArray(values: ULongArray): ULongArray = values.sortedArray()
        fun sortedDescendingCopyULongArray(values: ULongArray): ULongArray = values.sortedArrayDescending()
        fun searchULongArray(values: ULongArray, value: ULong): Int = values.binarySearch(value)

        fun maxUByteArray(values: UByteArray): UByte = values.max()
        fun minUByteArray(values: UByteArray): UByte = values.min()
        fun maxOrNullUByteArray(values: UByteArray): UByte? = values.maxOrNull()
        fun minOrNullUByteArray(values: UByteArray): UByte? = values.minOrNull()
        fun maxUShortArray(values: UShortArray): UShort = values.max()
        fun minUShortArray(values: UShortArray): UShort = values.min()
        fun maxOrNullUShortArray(values: UShortArray): UShort? = values.maxOrNull()
        fun minOrNullUShortArray(values: UShortArray): UShort? = values.minOrNull()
        fun maxUIntArray(values: UIntArray): UInt = values.max()
        fun minUIntArray(values: UIntArray): UInt = values.min()
        fun maxOrNullUIntArray(values: UIntArray): UInt? = values.maxOrNull()
        fun minOrNullUIntArray(values: UIntArray): UInt? = values.minOrNull()
        fun maxULongArray(values: ULongArray): ULong = values.max()
        fun minULongArray(values: ULongArray): ULong = values.min()
        fun maxOrNullULongArray(values: ULongArray): ULong? = values.maxOrNull()
        fun minOrNullULongArray(values: ULongArray): ULong? = values.minOrNull()
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], emit: .jvmJar)
            try JVMPreparationPhase().run(context)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        }
    }
}
#endif
