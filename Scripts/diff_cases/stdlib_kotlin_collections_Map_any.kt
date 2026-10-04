fun main() {
    val empty = emptyMap<String?, Int?>()
    val nonEmpty = mapOf<String?, Int?>(null to null, "value" to 1)

    println(empty.any())
    println(nonEmpty.any())
    println(nonEmpty.any { entry -> entry.key == null && entry.value == null })
    println(nonEmpty.any { false })
}
