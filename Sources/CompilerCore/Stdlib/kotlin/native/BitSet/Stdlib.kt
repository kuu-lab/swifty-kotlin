package kotlin.native

private const val BIT_SET_ELEMENT_SIZE: Int = 64

private fun bitSetElementSize(bitSize: Int): Int =
    (bitSize + BIT_SET_ELEMENT_SIZE - 1) / BIT_SET_ELEMENT_SIZE

/**
 * A vector of bits growing if necessary and allowing one to set, clear, and read bits by index.
 *
 * The public member family is migrated separately by KSP-1195. This declaration keeps the
 * constructor-owned storage so that the initializer constructor preserves Native semantics.
 */
@ObsoleteNativeApi
public class BitSet(size: Int = BIT_SET_ELEMENT_SIZE) {
    // Keep the constructor state in packed Long elements, matching Kotlin/Native's implementation.
    private var bits: LongArray = LongArray(bitSetElementSize(size))

    /** Creates a bit set of the given length and evaluates [initializer] for every index. */
    public constructor(length: Int, initializer: (Int) -> Boolean) : this(length) {
        var index = 0
        while (index < length) {
            setInitialBit(index, initializer(index))
            index += 1
        }
    }

    private fun setInitialBit(index: Int, value: Boolean) {
        val elementIndex = index / BIT_SET_ELEMENT_SIZE
        val bitOffset = index % BIT_SET_ELEMENT_SIZE
        val mask = 1L shl bitOffset
        bits[elementIndex] = if (value) {
            bits[elementIndex] or mask
        } else {
            bits[elementIndex] and mask.inv()
        }
    }

    public companion object {}
}
