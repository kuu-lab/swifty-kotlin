@file:kotlin.jvm.JvmName("CollectionToArray")
package kotlin.jvm.internal

private val EMPTY: Array<Any?> = arrayOfNulls<Any?>(0)

private fun collectionArrayCapacity(size: Int): Int {
    val grown = (size * 3 + 1) ushr 1
    if (grown > size) return grown
    if (size >= 2147483645) throw __jvmArrayCapacityError()
    return 2147483645
}

public fun toArray(collection: Collection<*>): Array<Any?> {
    val size = collection.size
    if (size == 0) return EMPTY
    val iterator = collection.iterator()
    if (!iterator.hasNext()) return EMPTY
    var result: Array<Any?> = arrayOfNulls<Any?>(size)
    var index = 0
    while (true) {
        result[index] = iterator.next()
        index++
        if (index >= result.size) {
            if (!iterator.hasNext()) return result
            result = __jvmCopyArray(result, collectionArrayCapacity(index))
        } else if (!iterator.hasNext()) {
            return __jvmCopyArray(result, index)
        }
    }
    return result
}

public fun toArray(collection: Collection<*>, array: Array<Any?>?): Array<Any?> {
    val input: Array<Any?> = array ?: throw NullPointerException()
    val size = collection.size
    if (size == 0) {
        if (input.size > 0) input[0] = null
        return input
    }
    val iterator = collection.iterator()
    if (!iterator.hasNext()) {
        if (input.size > 0) input[0] = null
        return input
    }
    // Arrays.copyOf preserves the supplied array's component type. Each next
    // value is stored immediately, before requesting another iterator value.
    var result: Array<Any?> = if (size <= input.size) input else __jvmCopyArray(input, size)
    var index = 0
    while (true) {
        result[index] = iterator.next()
        index++
        if (index >= result.size) {
            if (!iterator.hasNext()) return result
            result = __jvmCopyArray(result, collectionArrayCapacity(index))
        } else if (!iterator.hasNext()) {
            if (result === input) {
                input[index] = null
                return input
            }
            return __jvmCopyArray(result, index)
        }
    }
    return result
}
