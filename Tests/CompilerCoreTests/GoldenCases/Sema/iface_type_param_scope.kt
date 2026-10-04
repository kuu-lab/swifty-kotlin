package golden.sema

interface Holder<T> {
    fun get(): T
}

fun useHolder(h: Holder<Int>): Int = h.get()
