fun main() {
    val empty: Map<String?, Int?> = emptyMap()
    val values: Map<String?, Int?> = mapOf(null to null, "a" to 1, "b" to null)
    println(empty.count())
    println(values.count())
    println(values.count { it.key == null })
    println(values.count { it.value == null })
}
