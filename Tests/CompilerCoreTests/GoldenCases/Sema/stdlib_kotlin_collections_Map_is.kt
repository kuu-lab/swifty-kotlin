package golden.sema

private fun <K, V> mapIsNotEmpty(map: Map<out K, V>): Boolean = map.isNotEmpty()

private fun <K, V> mapIsNullOrEmpty(map: Map<out K, V>?): Boolean = map.isNullOrEmpty()

private fun <K, V> mapIsNullOrEmptyFromGeneric(map: Map<out K, V>?): Boolean {
    return map.isNullOrEmpty()
}

private fun collectionIsNullOrEmpty(values: Collection<Int>?): Boolean = values.isNullOrEmpty()

fun useMapIsFamily(
    empty: Map<String, Int>,
    nullable: Map<String?, Int?>?,
    projected: Map<String, Int?>
): Boolean {
    val nonEmpty = empty.isNotEmpty()
    val nullableResult = nullable.isNullOrEmpty()
    val projectedResult = mapIsNotEmpty<Any?, Int?>(projected)
    val genericNullableResult = mapIsNullOrEmptyFromGeneric(nullable)
    val collectionNullableResult = collectionIsNullOrEmpty(null)
    return nonEmpty || nullableResult || projectedResult || genericNullableResult || collectionNullableResult
}
