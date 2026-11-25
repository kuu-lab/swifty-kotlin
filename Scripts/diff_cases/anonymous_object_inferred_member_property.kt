class IteratorHost {
    fun make(): MutableIterator<String> = object : MutableIterator<String> {
        private var orderIndex = 0

        override fun hasNext(): Boolean = orderIndex < 2

        override fun next(): String {
            orderIndex++
            return if (orderIndex == 1) "a" else "b"
        }

        override fun remove() {}
    }
}

class PlainHost {
    fun make(): Any = object {
        private var count = 0

        fun next(): Int {
            count++
            return count
        }
    }
}

fun main() {
    val iterator = IteratorHost().make()
    println(iterator.next())
    println(iterator.hasNext())
    println(iterator.next())
}
