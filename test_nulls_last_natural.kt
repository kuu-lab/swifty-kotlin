import kotlin.comparisons.*

fun main() {
    val comp1 = nullsFirst<Int>()
    println(comp1.compare(null, 1)) // -1
    println(comp1.compare(1, null)) // 1
    println(comp1.compare(1, 2)) // -1

    val comp2 = nullsLast<Int>()
    println(comp2.compare(null, 1)) // 1
    println(comp2.compare(1, null)) // -1
    println(comp2.compare(1, 2)) // -1

    val comp3 = nullsLast(naturalOrder<Int>())
    println(comp3.compare(null, 1)) // 1
    println(comp3.compare(1, null)) // -1
    println(comp3.compare(1, 2)) // -1
}
