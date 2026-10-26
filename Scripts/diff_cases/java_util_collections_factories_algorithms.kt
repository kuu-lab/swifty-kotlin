// KOTLINC_FLAGS: -Xjdk-release=17
import java.util.Collections
import java.util.Random

fun <L : List<Int>> checkedSize(values: L): Int = Collections.checkedList(values, Int::class.java).size

@Suppress("UNCHECKED_CAST")
fun main() {
    val emptyList = Collections.emptyList<Int>()
    val emptySet = Collections.emptySet<Int>()
    val emptyMap = Collections.emptyMap<String, Int>()
    println("empty:${emptyList.isEmpty()}:${emptyList === Collections.emptyList<Int>()}:${emptySet.isEmpty()}:${emptyMap.isEmpty()}")
    try { emptyList.add(1) } catch (_: UnsupportedOperationException) { println("empty-list-readonly") }

    val singletonList = Collections.singletonList("one")
    val singletonSet = Collections.singleton("one")
    val singletonMap = Collections.singletonMap("one", 1)
    println("single:${singletonList.joinToString()}:${singletonSet.joinToString()}:${singletonMap["one"]}")
    try { singletonList[0] = "two" } catch (_: UnsupportedOperationException) { println("single-list-readonly") }
    println("copies:${Collections.nCopies(3, "x").joinToString()}")
    try { Collections.nCopies(2, 1).clear() } catch (_: UnsupportedOperationException) { println("copies-readonly") }

    val reverse = Collections.reverseOrder<Int>()
    println("reverse-order:${reverse.compare(1, 2)}:${Collections.reverseOrder<Int>(null).compare(1, 2)}")
    val sorted = mutableListOf(4, 1, 3, 2)
    Collections.sort(sorted)
    println("sort:${sorted.joinToString()}:${Collections.binarySearch(sorted, 3)}:${Collections.binarySearch(sorted, 5)}")
    Collections.sort(sorted, reverse)
    println("sort-reverse:${sorted.joinToString()}:${Collections.binarySearch(sorted, 2, reverse)}")
    val nullableSorted = mutableListOf<Int?>(2, null) as MutableList<Int>
    try { Collections.sort(nullableSorted) } catch (_: NullPointerException) { println("natural-null") }
    println("minmax:${Collections.min(listOf(3, 1, 2))}:${Collections.max(listOf(3, 1, 2), reverse)}")
    println("frequency:${Collections.frequency(listOf("a", null, "a"), "a")}:${Collections.frequency(listOf("a", null), null)}")
    println("disjoint:${Collections.disjoint(listOf(1, 2), listOf(3, 4))}:${Collections.disjoint(listOf(1, 2), listOf(2, 3))}")

    val filled = mutableListOf(1, 2, 3)
    Collections.fill(filled, 8)
    println("fill:${filled.joinToString()}")
    Collections.copy(filled, listOf(4, 5))
    println("copy:${filled.joinToString()}")
    val widenedDestination = mutableListOf<Any?>(null, null)
    Collections.copy(widenedDestination, listOf("a", "b"))
    println("copy-widened:${widenedDestination.joinToString()}")
    Collections.swap(filled, 0, 2)
    println("swap:${filled.joinToString()}")
    Collections.rotate(filled, -1)
    println("rotate:${filled.joinToString()}")
    Collections.reverse(filled)
    println("reverse:${filled.joinToString()}")
    println("replace:${Collections.replaceAll(filled, 5, 7)}:${Collections.replaceAll(filled, 9, 0)}:${filled.joinToString()}")
    println("sublist:${Collections.indexOfSubList(listOf(1, 2, 1, 2), listOf(1, 2))}:${Collections.lastIndexOfSubList(listOf(1, 2, 1, 2), listOf(1, 2))}:${Collections.lastIndexOfSubList(filled, emptyList<Int>())}")

    val set = linkedSetOf("a")
    println("add-all:${Collections.addAll(set, "a", "b")}:${Collections.addAll(set, "c")}:${set.joinToString()}")
    println("add-all-empty-readonly:${Collections.addAll(Collections.emptyList<Int>())}")
    val shuffled = mutableListOf(1, 2, 3, 4, 5)
    Collections.shuffle(shuffled, Random(42))
    println("shuffle:${shuffled.joinToString()}")
    val enumerated = Collections.enumeration(listOf("a", "b"))
    println("enumeration:${enumerated.hasMoreElements()}:${Collections.list(enumerated).joinToString()}:${enumerated.hasMoreElements()}")
    val emptyIterator = Collections.emptyIterator<Int>()
    val emptyListIterator = Collections.emptyListIterator<Int>()
    val emptyEnumeration = Collections.emptyEnumeration<Int>()
    println("empty-iterators:${emptyIterator.hasNext()}:${emptyListIterator.nextIndex()}:${emptyEnumeration.hasMoreElements()}")

    val checked = Collections.checkedList(mutableListOf<String>(), String::class.java)
    checked.add("ok")
    val rawChecked = checked as MutableList<Any?>
    try { rawChecked.add(1) } catch (_: ClassCastException) { println("checked-add") }
    try { rawChecked[0] = 2 } catch (_: ClassCastException) { println("checked-set") }
    val synchronized = Collections.synchronizedList(mutableListOf(1, 2))
    synchronized.add(3)
    synchronized.listIterator().add(0)
    println("synchronized:${synchronized.joinToString()}:${synchronized.subList(0, 2).joinToString()}")

    // KUU-3343: Java collection factory results expose Kotlin's size property.
    val checkedSize = Collections.checkedList(listOf(1), Int::class.java)
    val backing = mutableListOf(1, 2)
    val synchronizedSize = Collections.synchronizedList(backing)
    val unmodifiableSize = Collections.unmodifiableList(backing)
    println("sizes:${checkedSize.size}:${synchronizedSize.size}:${unmodifiableSize.size}:${java.util.LinkedList(backing).size}")
    backing.add(3)
    println("updated-sizes:${synchronizedSize.size}:${unmodifiableSize.size}")
    println("bounded-size:${checkedSize(listOf(1, 2))}")
}
