fun main() {
    val empty = emptyMap<String?, Int?>()
    val nonEmpty = mapOf<String?, Int?>(null to null, "value" to 1)
    val projected: Map<Any?, Number> = mapOf<Any?, Number>(null to 1, "value" to 2.0)

    println(empty.none())
    println(nonEmpty.none())
    println(projected.none())
    println(nonEmpty.none { entry -> entry.key == null && entry.value == null })
    println(nonEmpty.none { false })
    println(nonEmpty.isEmpty())
    println(emptyList<Int>().none())
    println(emptySet<Int>().none())
    println(emptySequence<Int>().none())
}
