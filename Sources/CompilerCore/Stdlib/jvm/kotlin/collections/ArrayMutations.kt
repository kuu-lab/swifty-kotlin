@file:kotlin.jvm.JvmName("ArraysKt")

package kotlin.collections

public fun <T> Array<T>.fill(element: T, fromIndex: Int = 0, toIndex: Int = size) {
    java.util.Arrays.fill(this, fromIndex, toIndex, element)
}

public fun IntArray.fill(element: Int, fromIndex: Int = 0, toIndex: Int = size) {
    java.util.Arrays.fill(this, fromIndex, toIndex, element)
}

public fun LongArray.fill(element: Long, fromIndex: Int = 0, toIndex: Int = size) {
    java.util.Arrays.fill(this, fromIndex, toIndex, element)
}

public fun <T> Array<out T>.copyInto(destination: Array<T>, destinationOffset: Int = 0, startIndex: Int = 0, endIndex: Int = size): Array<T> {
    java.lang.System.arraycopy(this, startIndex, destination, destinationOffset, endIndex - startIndex)
    return destination
}

public fun IntArray.copyInto(destination: IntArray, destinationOffset: Int = 0, startIndex: Int = 0, endIndex: Int = size): IntArray {
    java.lang.System.arraycopy(this, startIndex, destination, destinationOffset, endIndex - startIndex)
    return destination
}

public fun LongArray.copyInto(destination: LongArray, destinationOffset: Int = 0, startIndex: Int = 0, endIndex: Int = size): LongArray {
    java.lang.System.arraycopy(this, startIndex, destination, destinationOffset, endIndex - startIndex)
    return destination
}
