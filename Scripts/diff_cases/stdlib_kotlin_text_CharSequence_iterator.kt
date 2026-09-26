private class CountingCharSequence(private val value: String) : CharSequence {
    var lengthReads: Int = 0
    var getCalls: Int = 0

    override val length: Int
        get() {
            lengthReads++
            return value.length
        }

    override fun get(index: Int): Char {
        getCalls++
        return value[index]
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.substring(startIndex, endIndex)
}

fun main() {
    // for-in over the CharSequence extension iterator (UTF-16 code units).
    val source: CharSequence = "A\uD83D\uDE00b"
    val collected = StringBuilder()
    for (c in source) {
        collected.append(c.code).append(',')
    }
    println(collected.toString())

    // Explicit iterator protocol and exhaustion failure.
    val iterator = source.iterator()
    println(iterator.hasNext())
    println(iterator.nextChar().code)
    while (iterator.hasNext()) {
        iterator.nextChar()
    }
    try {
        iterator.nextChar()
    } catch (error: IndexOutOfBoundsException) {
        println("exhausted")
    }

    // Two iterators on the same receiver advance independently.
    val first = source.iterator()
    val second = source.iterator()
    first.nextChar()
    println(first.nextChar().code)
    println(second.nextChar().code)

    // Live view: a StringBuilder mutated after iterator() surfaces the append.
    val builder = StringBuilder("xy")
    val builderIterator = (builder as CharSequence).iterator()
    builderIterator.nextChar()
    builder.append('z')
    println(builderIterator.nextChar().code)
    println(builderIterator.hasNext())

    // Custom CharSequence drives length/get through the interface.
    val custom = CountingCharSequence("ab")
    val customIterator = custom.iterator()
    println(customIterator.nextChar().code)
    println(custom.lengthReads > 0)
    println(custom.getCalls)

    // Empty receiver: no elements, for-in body never runs.
    val empty: CharSequence = ""
    println(empty.iterator().hasNext())
    for (c in empty) {
        println("unreachable:" + c.code)
    }
}
