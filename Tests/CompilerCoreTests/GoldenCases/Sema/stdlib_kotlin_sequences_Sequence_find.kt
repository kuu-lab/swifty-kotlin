fun main() {
    val values: Sequence<Int?> = sequenceOf(null, 1, 2, null)
    val first: Int? = values.find { it == null }
    val last: Int? = values.findLast { it == null }
    println(first == null)
    println(last == null)
}
