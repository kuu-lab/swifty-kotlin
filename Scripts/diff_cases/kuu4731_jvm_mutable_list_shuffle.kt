// DIFF_JVM
import kotlin.random.Random

fun main() {
    val list = mutableListOf(1, 2, 3, 4, 5, 6, 7, 8)
    list.reverse()
    println(list)
    list.shuffle(Random(42))
    println(list)
    list.shuffle(Random(7))
    println(list)
    list.shuffle()
    println(list.sorted())

    val empty = mutableListOf<Int>()
    empty.reverse()
    empty.shuffle(Random(1))
    println(empty)

    val single = mutableListOf("a")
    single.reverse()
    single.shuffle()
    println(single)
}
