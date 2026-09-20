// `LinkedHashMap<K, V>` is a real `HashMap<K, V>` subclass (KUU-556;
// Sources/CompilerCore/Stdlib/kotlin/collections/LinkedHashMap.kt), matching
// the diff oracle (kotlinc-jvm: java.util.LinkedHashMap extends
// java.util.HashMap). This case verifies constructor type-argument inference
// and parameter / return / property types, including the upcast to
// MutableMap/HashMap. The rejected direction (a MutableMap-typed value is not
// necessarily a LinkedHashMap) is covered by the Diagnostics golden case
// linkedhashmap_mutablemap_argument_rejected.kt. Updates, lookups, entries
// HOFs, iteration and the `is HashMap`/`is LinkedHashMap` runtime identity are
// executed by Scripts/diff_cases/linkedhashmap_alias.kt and map_entries_hof.kt.

fun processLinkedMap(map: LinkedHashMap<String, Int>) {}

fun createLinkedMap(): LinkedHashMap<Int, String> {
    return LinkedHashMap<Int, String>()
}

class OrderedMapHolder {
    val scores: LinkedHashMap<String, Int> = LinkedHashMap()
    val labels: LinkedHashMap<Int, String> = LinkedHashMap<Int, String>()
}

fun main() {
    // Constructor inference from explicit type arguments alone: no expected
    // type here, so the inferred type is checked by the assignment and the
    // argument below instead.
    val explicit = LinkedHashMap<String, Int>()
    val explicitAsMutable: MutableMap<String, Int> = explicit
    val explicitAsHash: HashMap<String, Int> = explicit
    processLinkedMap(explicit)

    // Type-argument inference from the expected type, through MutableMap and
    // HashMap (both real supertypes now, not an alias target).
    val fromAlias: LinkedHashMap<Double, Boolean> = LinkedHashMap()
    val fromMutable: MutableMap<Int, String> = LinkedHashMap()
    val fromHash: HashMap<Int, String> = LinkedHashMap()

    // Return type propagation.
    val created = createLinkedMap()
    val createdAsMutable: MutableMap<Int, String> = created

    // Property type propagation.
    val holder = OrderedMapHolder()
    val scores: MutableMap<String, Int> = holder.scores
    val labels: LinkedHashMap<Int, String> = holder.labels
}
