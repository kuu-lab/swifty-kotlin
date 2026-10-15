package java.util

import kotlin.collections.contentHashCode

/** Primitive-array utility used by unchanged original stream regression bodies. */
public object Arrays {
    public fun fill(array: ByteArray, value: Byte) {
        for (index in array.indices) array[index] = value
    }

    /** Java's `Arrays.hashCode(int[])` overload, preserving JVM content hashing. */
    public fun hashCode(array: IntArray?): Int = array.contentHashCode()
}
