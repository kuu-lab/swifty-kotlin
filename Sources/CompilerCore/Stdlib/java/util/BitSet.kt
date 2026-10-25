@file:OptIn(kotlin.native.ObsoleteNativeApi::class)

package java.util

/** A Java-shaped bit set backed by the existing native bit-set implementation. */
public class BitSet private constructor(private val storage: kotlin.native.BitSet) {
    public constructor() : this(kotlin.native.BitSet())

    public constructor(nbits: Int) : this(kotlin.native.BitSet(nbits))

    public constructor(nbits: Int, initializer: (Int) -> Boolean) :
        this(kotlin.native.BitSet(nbits, initializer))

    public fun set(index: Int) {
        storage.set(index)
    }

    public fun set(index: Int, value: Boolean) {
        storage.set(index, value)
    }

    public fun set(fromIndex: Int, toIndex: Int) {
        storage.set(fromIndex, toIndex)
    }

    public fun set(fromIndex: Int, toIndex: Int, value: Boolean) {
        storage.set(fromIndex, toIndex, value)
    }

    public fun clear(index: Int) {
        storage.clear(index)
    }

    public fun clear(fromIndex: Int, toIndex: Int) {
        storage.clear(fromIndex, toIndex)
    }

    public fun clear() {
        storage.clear()
    }

    public fun flip(index: Int) {
        storage.flip(index)
    }

    public fun flip(fromIndex: Int, toIndex: Int) {
        storage.flip(fromIndex, toIndex)
    }

    public operator fun get(index: Int): Boolean = storage[index]

    public fun get(fromIndex: Int, toIndex: Int): BitSet {
        if (fromIndex < 0 || toIndex < fromIndex) throw IndexOutOfBoundsException()
        val result = BitSet(toIndex - fromIndex)
        var index = storage.nextSetBit(fromIndex)
        while (index >= 0 && index < toIndex) {
            result.set(index - fromIndex)
            index = storage.nextSetBit(index + 1)
        }
        return result
    }

    public fun nextSetBit(fromIndex: Int): Int = storage.nextSetBit(fromIndex)

    public fun nextClearBit(fromIndex: Int): Int = storage.nextClearBit(fromIndex)

    public fun previousSetBit(fromIndex: Int): Int = storage.previousSetBit(fromIndex)

    public fun previousClearBit(fromIndex: Int): Int = storage.previousClearBit(fromIndex)

    public fun cardinality(): Int {
        var result = 0
        var index = storage.nextSetBit(0)
        while (index >= 0) {
            result += 1
            index = storage.nextSetBit(index + 1)
        }
        return result
    }

    public fun length(): Int = storage.previousSetBit(storage.size - 1) + 1

    public fun isEmpty(): Boolean = storage.isEmpty

    public fun and(other: BitSet) {
        storage.and(other.storage)
    }

    public fun or(other: BitSet) {
        storage.or(other.storage)
    }

    public fun xor(other: BitSet) {
        storage.xor(other.storage)
    }

    public fun andNot(other: BitSet) {
        storage.andNot(other.storage)
    }

    public fun intersects(other: BitSet): Boolean = storage.intersects(other.storage)

    override fun equals(other: Any?): Boolean = other is BitSet && storage == other.storage

    override fun hashCode(): Int = storage.hashCode()

    override fun toString(): String = storage.toString()
}
