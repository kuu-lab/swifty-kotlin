// KOTLINC_FLAGS: -Xjdk-release=17
// KUU-2059: four Collections methods used by KotlinPoet at
// https://github.com/square/kotlinpoet/tree/4003e9aa402b50c65a2d809a2b43c7dfd8c7183e
// JVM oracle: Kotlin 2.3.10, -Xjdk-release=17. Copies are separate controls.
import java.util.Collections
import java.util.Collections as Views
import java.util.*

fun frozenList(values: MutableList<String>): List<String> = Collections.unmodifiableList(values)
fun frozenSet(values: MutableSet<String>): Set<String> = Collections.unmodifiableSet(values)
fun frozenMap(values: MutableMap<String, Int>): Map<String, Int> = Collections.unmodifiableMap(values)
fun keys(values: MutableMap<String, Boolean>): MutableSet<String> = Collections.newSetFromMap(values)
fun listCopy(values: List<String>): List<String> = values.toList()
fun setCopy(values: Set<String>): Set<String> = values.toSet()
fun mapCopy(values: Map<String, Int>): Map<String, Int> = values.toMap()
fun mutableList(values: MutableList<String>): MutableList<String> = Collections.unmodifiableList(values)
fun mutableSet(values: MutableSet<String>): MutableSet<String> = Collections.unmodifiableSet(values)
fun mutableMap(values: MutableMap<String, Int>): MutableMap<String, Int> = Collections.unmodifiableMap(values)
fun mutationSurface(values: MutableList<String>) { Collections.unmodifiableList(values).add("x") }

// Kotlin/JVM 2.4.20 rejects nullable arguments where these Java APIs require
// non-null collection element types. Runtime nullable cases remain below with
// signatures accepted by both compilers.

// Generic bodies from Util.jvm.kt lines 21-28 at the pinned upstream commit.
// Names and multiplatform modifiers are adapted for this standalone fixture.
fun <K, V> Map<K, V>.poetMap(): Map<K, V> =
    Collections.unmodifiableMap(LinkedHashMap(this))
fun <T> Collection<T>.poetList(): List<T> =
    Collections.unmodifiableList(ArrayList(this))
fun <T> Collection<T>.poetSet(): Set<T> =
    Collections.unmodifiableSet(LinkedHashSet(this))

private class CollectionsSourceMap : AbstractMutableMap<String, Int?>() {
    private val backing = linkedMapOf<String, Int?>()
    override val entries: MutableSet<MutableMap.MutableEntry<String, Int?>> get() = backing.entries
    override fun put(key: String, value: Int?): Int? = backing.put(key, value)
}

private class CollectionsSourceNames(private val values: List<String>) : kotlin.collections.AbstractCollection<String>() {
    override val size: Int get() = values.size
    override fun iterator(): kotlin.collections.Iterator<String> = values.iterator()
}

fun <C : Collection<String>> qualifiedCollectionCopy(values: C): List<String> =
    kotlin.collections.ArrayList<String>(values)

private data class CollectionsIdentityToken(val id: Int)

fun denied(label: String, operation: () -> Unit) {
    try {
        operation()
        println("missed:$label")
    } catch (_: UnsupportedOperationException) {
        println("uoe:$label")
    }
}

fun main() {
    val list = mutableListOf("a", "b")
    val view: MutableList<String> = mutableList(list)
    val copy = listCopy(list)
    list[0] = "c"
    list.add("d")
    println("list:${view.joinToString(",")}:${copy.joinToString(",")}:${view === list}")
    println("random-access:${view is RandomAccess}:${view.subList(0, 1) is RandomAccess}")
    println("readonly:${frozenList(list).size}:${view == list}:${view.hashCode() == list.hashCode()}")
    val sub = view.subList(0, 2)
    list[1] = "e"
    println("sub:${sub.joinToString(",")}")
    val iter = view.listIterator(1)
    println("iterator:${iter.nextIndex()}:${iter.next()}:${iter.previous()}:${iter.previousIndex()}")
    denied("list-add") { view.add("x") }
    denied("list-set") { view[0] = "x" }
    denied("list-remove") { view.remove("missing") }
    denied("list-add-empty") { view.addAll(emptyList()) }
    denied("list-add-index") { view.add(0, "x") }
    denied("list-addAll-index") { view.addAll(0, emptyList()) }
    denied("list-removeAt") { view.removeAt(0) }
    denied("list-removeAll") { view.removeAll(emptyList()) }
    denied("list-retainAll") { view.retainAll(list) }
    denied("list-clear") { view.clear() }
    denied("list-iterator-remove") { view.iterator().remove() }
    denied("list-iterator-add") { iter.add("x") }
    denied("list-iterator-set") { iter.set("x") }
    denied("list-iterator-delete") { iter.remove() }
    denied("sub-clear") { sub.clear() }
    denied("list-plus") { view += "x" }

    val set = linkedSetOf("a")
    val setView: MutableSet<String> = Views.unmodifiableSet(set)
    val setSnapshot = setCopy(set)
    set.add("b")
    println("set:${setView.joinToString(",")}:${setSnapshot.joinToString(",")}:${setView === set}")
    println("readonly-set:${frozenSet(set).size}:${setView == set}:${setView.hashCode() == set.hashCode()}")
    denied("set-plus") { setView += "x" }
    denied("set-add") { setView.add("x") }
    denied("set-remove") { setView.remove("missing") }
    denied("set-clear") { setView.clear() }
    denied("set-addAll") { setView.addAll(emptySet()) }
    denied("set-addAll-array-empty") { setView.addAll(emptyArray<String>()) }
    denied("set-addAll-array") { setView.addAll(arrayOf("x")) }
    denied("set-removeAll") { setView.removeAll(emptySet()) }
    denied("set-retainAll") { setView.retainAll(set) }
    val setIter = setView.iterator()
    println("set-iterator:${setIter.next()}")
    denied("set-iterator") { setIter.remove() }

    val map = linkedMapOf("a" to 1)
    val mapView = mutableMap(map)
    val mapSnapshot = mapCopy(map)
    val mapKeys = mapView.keys
    val mapValues = mapView.values
    val mapEntries = mapView.entries
    map["a"] = 2
    map["b"] = 3
    println("map:${mapView["a"]}:${mapView.size}:${mapSnapshot["a"]}:${mapView === map}")
    println("readonly-map:${frozenMap(map).size}:${mapView == map}:${mapView.hashCode() == map.hashCode()}")
    println("map-views:${mapKeys.joinToString(",")}:${mapValues.joinToString(",")}:${mapEntries.size}")
    val entry = mapEntries.iterator().next()
    println("entry:${entry.key}:${entry.value}:${entry == map.entries.iterator().next()}")
    val secondEntry = mapEntries.iterator().next()
    val backingEntry = map.entries.iterator().next()
    println("entry-equality:${entry == secondEntry}:${backingEntry == entry}:${mapEntries.contains(secondEntry)}")
    val entryLookup = mapOf(backingEntry to "entry")
    println("entry-hash:${entry.hashCode() == backingEntry.hashCode()}:${setOf(backingEntry).contains(entry)}:${setOf(entry).contains(backingEntry)}:${entryLookup[entry]}")
    denied("map-put") { mapView["c"] = 4 }
    denied("map-remove") { mapView.remove("missing") }
    denied("map-clear") { mapView.clear() }
    denied("map-putAll") { mapView.putAll(emptyMap()) }
    denied("map-keys") { mapKeys.clear() }
    denied("map-values") { mapValues.remove(2) }
    denied("map-entries") { mapEntries.clear() }
    denied("map-entry") { entry.setValue(4) }
    val entryIter = mapEntries.iterator()
    entryIter.next()
    denied("map-entry-iterator") { entryIter.remove() }

    println("poet:${list.poetList().joinToString(",")}:${set.poetSet().joinToString(",")}:${map.poetMap()["a"]}")
    val qualifiedCopy = kotlin.collections.ArrayList<String>(list)
    val qualifiedCapacity = kotlin.collections.ArrayList<String>(2)
    qualifiedCapacity.add("capacity")
    println("array-list-constructor:${qualifiedCopy.joinToString(",")}:${qualifiedCapacity.size}")
    try { kotlin.collections.ArrayList<String>(-1) }
    catch (_: IllegalArgumentException) { println("array-list-negative-capacity") }
    val sourceNames = CollectionsSourceNames(listOf("source", "copy"))
    println("array-list-source-copy:${kotlin.collections.ArrayList<String>(sourceNames).joinToString(",")}:${qualifiedCollectionCopy(sourceNames).joinToString(",")}")
    val ordered = TreeMap<String, Int>(Comparator { a, b -> a.length - b.length })
    ordered["a"] = 3
    val orderedView = Collections.unmodifiableMap(ordered)
    println("map-comparator:${orderedView["b"]}:${orderedView.containsKey("b")}")
    val nullableOrdered = TreeMap<String, Int?>(Comparator { a, b -> a.length - b.length })
    nullableOrdered["a"] = null
    val nullableOrderedMap: Map<String, Int?> = nullableOrdered
    val nullableOrderedView = Collections.unmodifiableMap(nullableOrderedMap)
    println("map-null-key:${nullableOrderedMap.containsKey("b")}:${nullableOrderedView.containsKey("b")}:${nullableOrderedView.containsKey("absent")}")
    val sourceMap = CollectionsSourceMap()
    val sourceMapView: Map<String, Int?> = sourceMap
    val sourceMapEmpty = sourceMapView.containsKey("present")
    sourceMap["present"] = 7
    sourceMap["null"] = null
    val frozenSourceMap = Collections.unmodifiableMap(sourceMapView)
    println("source-map:$sourceMapEmpty:${sourceMapView.containsKey("present")}:${sourceMapView.containsKey("null")}:${sourceMapView.containsKey("absent")}:${frozenSourceMap.containsKey("null")}:${frozenSourceMap["present"]}")

    val identityKey = CollectionsIdentityToken(1)
    val identityValue = CollectionsIdentityToken(2)
    val equalIdentityKey = CollectionsIdentityToken(1)
    val equalIdentityValue = CollectionsIdentityToken(2)
    val identityMap: MutableMap<CollectionsIdentityToken, CollectionsIdentityToken> = IdentityHashMap()
    identityMap[identityKey] = identityValue
    val identityView = Collections.unmodifiableMap(identityMap)
    val identityEntry = identityMap.entries.first()
    val protectedIdentityEntry = identityView.entries.first()
    val equalIdentityEntry = mutableMapOf(equalIdentityKey to equalIdentityValue).entries.first()
    println("identity-map:${identityView.containsKey(identityKey)}:${identityView.containsKey(equalIdentityKey)}:${identityView.containsValue(equalIdentityValue)}")
    println("identity-entry:${identityView.entries.contains(identityEntry)}:${identityView.entries.contains(equalIdentityEntry)}:${identityView.entries.containsAll(listOf(equalIdentityEntry))}:${identityView.entries == setOf(equalIdentityEntry)}")
    println("identity-entry-hash:${identityEntry.hashCode() == protectedIdentityEntry.hashCode()}:${setOf(identityEntry).contains(protectedIdentityEntry)}:${setOf(protectedIdentityEntry).contains(identityEntry)}:${mapOf(identityEntry to "identity")[protectedIdentityEntry]}")

    // Do not access the supplied map after creating the set (JDK contract).
    val fromMap = keys(linkedMapOf<String, Boolean>())
    println("new:${fromMap.add("a")}:${fromMap.add("a")}:${fromMap.add("b")}:${fromMap.joinToString(",")}")
    val fromMapIter = fromMap.iterator()
    println("new-iterator:${fromMapIter.next()}")
    fromMapIter.remove()
    println("new-remove:${fromMap.contains("a")}:${fromMap.remove("b")}:${fromMap.remove("b")}:${fromMap.isEmpty()}")
    fromMap.addAll(listOf("c", "d"))
    fromMap.retainAll(setOf("d"))
    println("new-retain:${fromMap.joinToString(",")}")
    fromMap.clear()
    println("new-clear:${fromMap.size}")
    println("new-array:${fromMap.addAll(emptyArray<String>())}:${fromMap.addAll(arrayOf("x", "y"))}:${fromMap.joinToString(",")}")
    fromMap.clear()
    val nullableBoolean = Collections.newSetFromMap<String>(linkedMapOf<String, Boolean?>())
    val nullableKeyMap = Collections.newSetFromMap<String>(linkedMapOf<String?, Boolean>())
    println("nullable-key-map:${nullableKeyMap.add("x")}:${nullableKeyMap.remove("x")}")
    println("nullable-boolean:${nullableBoolean.add("x")}:${nullableBoolean.remove("x")}")
    try {
        keys(mutableMapOf("x" to false))
    } catch (_: IllegalArgumentException) {
        println("non-empty-map")
    }

    val nullableList: MutableList<String?> = Views.unmodifiableList(listOf(null, "n"))
    val nullableSet: MutableSet<String?> = Views.unmodifiableSet(setOf(null, "n"))
    val nullableMap: MutableMap<String?, Int?> = Views.unmodifiableMap(mapOf(null to null, "n" to 4))
    val nullableKeys: MutableSet<String?> = Collections.newSetFromMap(linkedMapOf<String?, Boolean>())
    nullableKeys.add(null)
    println("nullable:${nullableList[0]}:${nullableSet.contains(null)}:${nullableMap.containsKey(null)}:${nullableKeys.contains(null)}")
    val widenedList: MutableList<Any?> = Collections.unmodifiableList<Any?>(listOf("wide", null))
    val widenedMap: MutableMap<Any?, Any?> = Collections.unmodifiableMap<Any?, Any?>(mapOf("wide" to 4))
    println("wide:${widenedList.size}:${widenedMap["wide"]}")
    val platformList: MutableList<String?> = Collections.unmodifiableList<String>(listOf(null, "p"))
    val platformSet: MutableSet<String?> = Collections.unmodifiableSet<String>(setOf(null, "p"))
    val platformMap: MutableMap<String?, Int?> = Collections.unmodifiableMap<String, Int>(mapOf(null to null, "p" to 5))
    val platformKeys: MutableSet<String?> = Collections.newSetFromMap<String>(linkedMapOf<String, Boolean>())
    platformKeys.add(null)
    println("platform:${platformList[0]}:${platformSet.contains(null)}:${platformMap.containsKey(null)}:${platformKeys.contains(null)}")
    try { Collections.unmodifiableList<String>(null) } catch (_: NullPointerException) { println("npe:list") }
    try { Collections.unmodifiableSet<String>(null) } catch (_: NullPointerException) { println("npe:set") }
    try { Collections.unmodifiableMap<String, Int>(null) } catch (_: NullPointerException) { println("npe:map") }
    try { Collections.newSetFromMap<String>(null) } catch (_: NullPointerException) { println("npe:new") }
}
