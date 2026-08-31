private fun asInt(value: Boolean): Int = if (value) 1 else 0

private fun <K, V> mapIsNotEmpty(map: Map<out K, V>): Boolean = map.isNotEmpty()

private fun <K, V> mapIsNullOrEmpty(map: Map<out K, V>?): Boolean = map.isNullOrEmpty()

private fun <K, V> mapIsNullOrEmptyFromGeneric(map: Map<out K, V>?): Boolean {
    return map.isNullOrEmpty()
}

private fun collectionIsNullOrEmpty(values: Collection<Int>?): Boolean = values.isNullOrEmpty()

fun main() {
    val empty: Map<String, Int> = emptyMap()
    val nonEmpty: Map<String, Int?> = mapOf("present" to null)
    val nullableKeyAndValue: Map<String?, Int?> = mapOf(null to null)

    println(asInt(empty.isNotEmpty()))
    println(asInt(nonEmpty.isNotEmpty()))
    println(asInt(empty.isNullOrEmpty()))
    println(asInt(nonEmpty.isNullOrEmpty()))
    println(asInt(nullableKeyAndValue.isNotEmpty()))
    println(asInt(mapIsNotEmpty<Any?, Int?>(nonEmpty)))
    println(asInt(mapIsNullOrEmpty<Any?, Int?>(null)))
    println(asInt(mapIsNullOrEmptyFromGeneric(nullableKeyAndValue)))
    println(asInt(collectionIsNullOrEmpty(null)))

    var evaluations = 0
    fun evaluatedMap(): Map<String, Int>? {
        evaluations++
        return null
    }
    println(asInt(evaluatedMap().isNullOrEmpty()))
    println(evaluations)
}
