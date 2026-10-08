// KSP-1004: Map.contains is the key-membership operator and explicit extension call.
// KUU-1597 Sema owner: pin Map.contains/in key binding, nullable key types, and delegated Map resolution; membership results stay in Scripts/diff_cases/stdlib_kotlin_collections_Map_contains.kt.
private data class EqualKey(val value: Int)

private class CustomMap(private val backing: Map<String, Int?>) : Map<String, Int?> by backing

private fun customMapContains(custom: CustomMap): Boolean = custom.contains("custom")

fun main() {
    val map: Map<String, Int?> = mapOf("present" to null, "number" to 1)
    val present: Boolean = "present" in map
    val missing: Boolean = "missing" in map
    val explicitPresent: Boolean = map.contains("present")
    val nullValue: Boolean = map.containsValue(null)
    val integerValue: Boolean = map.containsValue(1)

    val nullableMap: Map<String?, Int?> = mapOf(null to null, "value" to 2)
    val nullableKey: String? = null
    val nullableMembership: Boolean = nullableKey in nullableMap
    val explicitNullKey: Boolean = nullableMap.contains(null)

    val equalKeys: Map<EqualKey, String?> = mapOf(EqualKey(7) to null)
    val equalKeyMembership: Boolean = EqualKey(7) in equalKeys
    val missingEqualKey: Boolean = equalKeys.contains(EqualKey(8))

    val boxedKeys: Map<Int, String?> = mapOf(1 to null)
    val boxedMembership: Boolean = 1 in boxedKeys
    val missingBoxedKey: Boolean = boxedKeys.contains(2)
    val delegatedMembership: Boolean = customMapContains(CustomMap(mapOf("custom" to 1)))
}
