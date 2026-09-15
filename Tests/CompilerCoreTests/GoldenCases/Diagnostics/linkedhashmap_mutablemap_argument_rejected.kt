// `LinkedHashMap<K, V>` is a real `HashMap` subclass (KUU-556), matching the
// diff oracle (kotlinc-jvm: java.util.LinkedHashMap extends
// java.util.HashMap). A `MutableMap`-typed value is not necessarily a
// LinkedHashMap, so passing one where a LinkedHashMap parameter is expected
// is rejected -- see linkedhashmap_alias.kt (GoldenCases/Sema) for the
// supported upcast direction (LinkedHashMap -> MutableMap/HashMap).
fun processLinkedMap(map: LinkedHashMap<String, Int>) {}

fun main() {
    val explicitAsMutable: MutableMap<String, Int> = LinkedHashMap()
    processLinkedMap(explicitAsMutable)
}
