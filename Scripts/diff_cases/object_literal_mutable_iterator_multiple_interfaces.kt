// KUU-477: Iterator must dispatch correctly when another interface occupies
// an earlier itable slot on the same object expression.
interface Marker {
    fun marker(): Int
}

class Counter : MutableIterable<Int> {
    override fun iterator(): MutableIterator<Int> {
        return object : Marker, MutableIterator<Int> {
            var i = 0

            override fun marker(): Int = 0
            override fun hasNext() = i < 3
            override fun next(): Int {
                val value = i
                i++
                return value
            }

            override fun remove() {}
        }
    }
}

fun printAll(source: MutableIterable<Int>) {
    val iter = source.iterator()
    while (iter.hasNext()) {
        print(iter.next())
        print(" ")
    }
}

fun main() {
    printAll(Counter())
}
