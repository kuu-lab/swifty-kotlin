// KUU-1361: sorted collection API family — Iterable/List/Set/Array/primitive
// toSortedSet, toSortedMap, sortedSetOf/sortedMapOf, and the
// java.util SortedSet/NavigableSet/TreeSet/SortedMap/NavigableMap/TreeMap
// surface including navigation and descending views.
import java.util.NavigableMap
import java.util.NavigableSet
import java.util.SortedMap
import java.util.SortedSet
import java.util.TreeMap
import java.util.TreeSet

fun main() {
    // Conversions
    println(listOf(3, 1, 2).toSortedSet())
    println(setOf(6, 4, 5).toSortedSet())
    println(arrayOf(3, 1, 2).toSortedSet())
    println(sequenceOf(9, 7, 8).toSortedSet())
    println(intArrayOf(3, 1, 2).toSortedSet())
    println(charArrayOf('c', 'a', 'b').toSortedSet())
    println(mapOf("b" to 2, "a" to 1).toSortedMap())

    // Comparator overloads and factories
    println(listOf(1, 2, 3).toSortedSet(Comparator { a: Int, b: Int -> b - a }))
    println(sortedSetOf(3, 1, 2))
    println(sortedSetOf(Comparator { a: Int, b: Int -> b - a }, 1, 2, 3))
    println(sortedMapOf("b" to 2, "a" to 1))
    println(sortedMapOf(Comparator { a: String, b: String -> b.compareTo(a) }, "a" to 1, "b" to 2))

    // is checks across the hierarchy
    val treeSet = TreeSet(listOf(3, 1, 2))
    println(treeSet is TreeSet<Int>)
    println(treeSet is NavigableSet<Int>)
    println(treeSet is SortedSet<Int>)
    println(treeSet is MutableSet<Int>)
    val treeMap = TreeMap(mapOf("b" to 2, "a" to 1))
    println(treeMap is TreeMap<String, Int>)
    println(treeMap is NavigableMap<String, Int>)
    println(treeMap is SortedMap<String, Int>)
    println(treeMap is MutableMap<String, Int>)

    // Set navigation through interface-typed receivers
    val ns: NavigableSet<Int> = TreeSet(listOf(1, 3, 5, 7))
    println(ns.lower(5))
    println(ns.floor(4))
    println(ns.ceiling(4))
    println(ns.higher(5))
    println(ns.lower(1) ?: "null")
    println(ns.higher(7) ?: "null")
    println(ns.pollFirst())
    println(ns.pollLast())
    println(ns)

    // Map navigation through interface-typed receivers
    val nm: NavigableMap<String, Int> = TreeMap(mapOf("a" to 1, "c" to 3, "e" to 5))
    println(nm.lowerKey("c"))
    println(nm.floorKey("d"))
    println(nm.ceilingKey("d"))
    println(nm.higherKey("c"))
    println(nm.lowerKey("a") ?: "null")
    println(nm.firstEntry())
    println(nm.lastEntry())
    println(nm.pollFirstEntry())
    println(nm.pollLastEntry())
    println(nm)

    // Descending live views write through to the parent
    val ds = TreeSet(listOf(1, 2, 3, 4))
    val desc = ds.descendingSet()
    println(desc)
    desc.add(5)
    println(ds)
    val di = ds.descendingIterator()
    while (di.hasNext()) print(di.next())
    println()
    val dm = TreeMap(mapOf("a" to 1, "b" to 2, "c" to 3))
    println(dm.descendingMap())
    println(dm.descendingKeySet())
    println(ds.first())
    println(ds.last())
    println(dm.firstKey())
    println(dm.lastKey())
}
