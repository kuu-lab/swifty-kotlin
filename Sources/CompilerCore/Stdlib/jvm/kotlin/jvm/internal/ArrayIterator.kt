package kotlin.jvm.internal

public fun <T> iterator(array: Array<out T>): Iterator<T> = object : Iterator<T> {
    private var index = 0

    override fun hasNext(): Boolean = index < array.size

    override fun next(): T {
        if (!hasNext()) throw NoSuchElementException(index.toString())
        return array[index++]
    }
}
