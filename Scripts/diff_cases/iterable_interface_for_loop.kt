// BUG-167: `for (x in xs)` over a value statically typed as an iterable
// *interface* (`Iterable<T>`, `Collection<T>`, ...) or as a source class
// implementing `Iterable` used to fall back to the range-iterator intrinsics,
// reinterpreting the collection object as a range and yielding garbage
// elements.
class Counter(val n: Int) : Iterable<Int> {
    override fun iterator(): Iterator<Int> = CounterIterator(n)
}

class CounterIterator(val n: Int) : Iterator<Int> {
    var i = 0
    override fun hasNext(): Boolean = i < n
    override fun next(): Int {
        val v = i
        i = i + 1
        return v
    }
}

fun printAll(xs: Iterable<Int>) {
    for (x in xs) {
        println(x)
    }
}

fun pick(s: String, indices: Iterable<Int>): String {
    val sb = StringBuilder()
    for (i in indices) {
        sb.append(s[i])
    }
    return sb.toString()
}

fun sum(xs: Collection<Int>): Int {
    var total = 0
    for (x in xs) {
        total += x
    }
    return total
}

fun printPairs(ps: Iterable<Pair<Int, String>>) {
    for ((a, b) in ps) {
        println("" + a + b)
    }
}

fun main() {
    printAll(listOf(0, 2, 4))
    printAll(setOf(7))
    printAll(Counter(3))
    println(pick("abcdef", listOf(1, 3, 5)))
    println("abcdef".slice(listOf(1, 3, 5)))
    println(sum(listOf(1, 2, 3)))
    printPairs(listOf(Pair(1, "a"), Pair(2, "b")))
    for (x in listOf(9, 8)) {
        println(x)
    }
    for (i in 0..2) {
        println(i)
    }
}
