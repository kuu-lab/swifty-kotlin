package java.util

/** Primitive-array utility used by unchanged original stream regression bodies. */
public object Arrays {
    public fun fill(array: ByteArray, value: Byte) {
        for (index in array.indices) array[index] = value
    }
}
