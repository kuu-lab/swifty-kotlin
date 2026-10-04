// KSP-1004: Map.contains is the key-membership operator and explicit extension call.
private data class EqualKey(val value: Int)

private class CustomMap(private val backing: Map<String, Int?>) : Map<String, Int?> by backing

private fun customMapContains(custom: CustomMap): Boolean = custom.contains("custom")

fun main() {
    val map: Map<String, Int?> = mapOf("present" to null, "number" to 1)
    println("present" in map)
    println("missing" in map)
    println(map.contains("present"))
    println(map.contains("missing"))
    println(map.containsValue(null))
    println(map.containsValue(1))

    val nullableMap: Map<String?, Int?> = mapOf(null to null, "value" to 2)
    val nullableKey: String? = null
    println(nullableKey in nullableMap)
    println(nullableMap.contains(null))
    println(nullableMap.containsValue(null))

    val equalKeys: Map<EqualKey, String?> = mapOf(EqualKey(7) to null)
    println(EqualKey(7) in equalKeys)
    println(equalKeys.contains(EqualKey(8)))

    val boxedKeys: Map<Int, String?> = mapOf(1 to null)
    println(1 in boxedKeys)
    println(boxedKeys.contains(2))

}
