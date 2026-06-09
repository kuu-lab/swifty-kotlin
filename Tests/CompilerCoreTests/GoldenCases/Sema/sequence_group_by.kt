fun main() {
    // groupBy on sequenceOf - String by length
    val seq = sequenceOf("a", "bb", "cc", "ddd")
    val grouped = seq.groupBy { it.length }
    println(grouped[1])
    println(grouped[2])
    println(grouped[3])

    // groupBy on list.asSequence() - Int by parity
    val list = listOf(1, 2, 3, 4, 5)
    val byParity = list.asSequence().groupBy { if (it % 2 == 0) "even" else "odd" }
    println(byParity["odd"])
    println(byParity["even"])
}
