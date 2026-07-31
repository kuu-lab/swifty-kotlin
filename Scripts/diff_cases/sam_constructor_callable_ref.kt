// BUG-048: a callable reference used in SAM-conversion position
// (`Comparator<Int>(::myCompare)`) must be lowered to an object implementing
// the functional interface, exactly like the equivalent lambda literal.
// It used to be lowered as a bare callable value, so interface dispatch on
// the result crashed at runtime with a vtable/itable lookup failure.
fun myCompare(a: Int, b: Int): Int = a - b

fun label(value: Int): String = "v=$value"

fun interface Stringify {
    fun render(value: Int): String
}

class Holder(val bias: Int) {
    fun cmp(a: Int, b: Int): Int = (a - b) + bias
}

fun main() {
    val fromRef = Comparator<Int>(::myCompare)
    println(fromRef.compare(3, 5))

    val fromLambda = Comparator<Int> { a, b -> myCompare(a, b) }
    println(fromLambda.compare(3, 5))

    val bound = Comparator<Int>(Holder(100)::cmp)
    println(bound.compare(3, 5))

    println(Stringify(::label).render(42))

    val list = mutableListOf(5, 1, 3)
    list.sortWith(Comparator<Int>(::myCompare))
    println(list)
    println(listOf(4, 2, 9).sortedWith(fromRef))
}
