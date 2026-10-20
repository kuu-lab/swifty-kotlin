package kotlin.jvm.internal
open class SpreadBuilder(size: Int) {
    private val values = mutableListOf<Any?>()
    fun size(): Int = values.size
    fun add(value: Any?) { values.add(value) }
    fun addSpread(value: Any?) {
        if (value == null) return
        if (value is Array<*>) { for (element in value) values.add(element); return }
        if (value is Iterable<*>) { for (element in value) values.add(element); return }
        if (value is Iterator<*>) { while (value.hasNext()) values.add(value.next()); return }
        throw UnsupportedOperationException("Don't know how to spread $value")
    }
    fun toArray(array: Array<Any?>): Array<Any?> {
        val result = if (array.size < values.size) __jvmCopyArray(array, values.size) else array
        var index = 0
        while (index < values.size) { result[index] = values[index]; index++ }
        if (result.size > values.size) result[values.size] = null
        return result
    }
}
abstract class PrimitiveSpreadBuilder<T>(private val capacity: Int) {
    private val spreads = arrayOfNulls<Any?>(capacity)
    protected var position: Int = 0
    protected abstract fun getSize(value: T): Int
    fun addSpread(value: T) { spreads[position++] = value }
    protected fun size(): Int {
        var result = 0
        var index = 0
        while (index < capacity) {
            val spread = spreads[index]
            result += if (spread == null) 1 else getSize(spread as T)
            index++
        }
        return result
    }
    protected fun toArray(values: T, result: T): T {
        var sourceIndex = 0
        var targetIndex = 0
        var index = 0
        while (index < capacity) {
            val spread = spreads[index]
            if (spread != null) {
                val count = index - sourceIndex
                __jvmArrayCopy(values, sourceIndex, result, targetIndex, count)
                targetIndex += count
                val spreadSize = getSize(spread as T)
                __jvmArrayCopy(spread, 0, result, targetIndex, spreadSize)
                targetIndex += spreadSize
                sourceIndex = index + 1
            }
            index++
        }
        __jvmArrayCopy(values, sourceIndex, result, targetIndex, capacity - sourceIndex)
        return result
    }
}
