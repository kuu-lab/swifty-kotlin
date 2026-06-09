fun main() {
    val seq = sequenceOf("a", "bb", "ccc", "dd", "e")

    val dest = mutableMapOf<Int, MutableList<String>>()
    val result = seq.groupByTo(dest) { it.length }
    println(result[1])
    println(result[2])
    println(result[3])
}
