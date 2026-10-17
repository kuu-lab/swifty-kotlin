package java.util

import kotlin.collections.contentHashCode

public object Arrays {
    public fun fill(array: ByteArray, value: Byte) {
        for (index in array.indices) array[index] = value
    }

    public fun hashCode(array: IntArray?): Int = array.contentHashCode()
}
