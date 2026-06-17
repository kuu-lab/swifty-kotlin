import kotlin.comparisons.*

fun main() {
    val comp: Comparator<Int?> = nullsFirst(naturalOrder<Int>())
    println(comp.compare(1, 2))
}
