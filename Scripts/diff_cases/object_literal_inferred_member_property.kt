// An object literal's inferred member properties must be finalized before its
// member function bodies are checked (KUU-4610). kotlinc prints 10, 21, false.
class NumberBox(private val source: Iterable<Int>) {
    fun iterator(): Iterator<Int> = object : Iterator<Int> {
        private val iterator = source.iterator()
        private var index = 0

        override fun hasNext(): Boolean = iterator.hasNext()

        override fun next(): Int {
            if (index < 0) throw ArithmeticException("Index overflow has happened.")
            val result = index + iterator.next()
            index++
            return result
        }
    }
}

fun main() {
    val iterator = NumberBox(listOf(10, 20)).iterator()
    println(iterator.next())
    println(iterator.next())
    println(iterator.hasNext())
}
