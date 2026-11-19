fun Sequence<Int>.flatMapTo(destination: MutableList<Int>, transform: (Int) -> Iterable<Int>): Int = 7

fun main() {
    println(sequenceOf(1).flatMapTo(mutableListOf<Int>()) { listOf(it) })
}
