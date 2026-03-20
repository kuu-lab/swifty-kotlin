fun main() {
    // === toMutableList() from List ===
    val sourceList = listOf(1, 2, 2)
    val copiedList = sourceList.toMutableList()
    copiedList.add(3)
    println(sourceList)
    println(copiedList)

    // toMutableList() returns independent copy
    val original = listOf("a", "b", "c")
    val mutable = original.toMutableList()
    mutable[0] = "z"
    mutable.add("d")
    println(original)
    println(mutable)

    // toMutableList() from empty list
    val emptyList = emptyList<Int>()
    val emptyMutable = emptyList.toMutableList()
    println(emptyMutable)
    println(emptyMutable.size)
    emptyMutable.add(42)
    println(emptyMutable)

    // toMutableList() from Set (Iterable.toMutableList)
    val set = setOf(10, 20, 30)
    val listFromSet = set.toMutableList()
    listFromSet.add(40)
    println(listFromSet)
    println(listFromSet.size)

    // toMutableList() from MutableList (creates a copy)
    val mutableOrig = mutableListOf(1, 2, 3)
    val mutableCopy = mutableOrig.toMutableList()
    mutableCopy.add(4)
    mutableOrig.add(5)
    println(mutableOrig)
    println(mutableCopy)

    // toMutableList() type is MutableList
    val result = listOf(1, 2, 3).toMutableList()
    result.add(4)
    result.remove(1)
    println(result)

    // toMutableList() preserves order
    val ordered = listOf(5, 3, 1, 4, 2)
    val orderedMutable = ordered.toMutableList()
    println(orderedMutable)

    // toMutableList() with nulls
    val withNulls = listOf<String?>(null, "a", null, "b")
    val mutableNulls = withNulls.toMutableList()
    mutableNulls.add("c")
    mutableNulls.add(null)
    println(mutableNulls)

    // Chaining: toMutableList then sort
    val unsorted = listOf(3, 1, 4, 1, 5)
    val sorted = unsorted.toMutableList()
    sorted.sort()
    println(unsorted)
    println(sorted)

    // toMutableList() from IntRange
    val rangeList = (1..5).toMutableList()
    rangeList.add(6)
    println(rangeList)

    // Multiple toMutableList() calls create independent copies
    val base = listOf(1, 2, 3)
    val copy1 = base.toMutableList()
    val copy2 = base.toMutableList()
    copy1.add(10)
    copy2.add(20)
    println(base)
    println(copy1)
    println(copy2)

    // toMutableList() with removeAt
    val toRemove = listOf("x", "y", "z").toMutableList()
    toRemove.removeAt(1)
    println(toRemove)

    // toMutableList() with clear
    val toClear = listOf(1, 2, 3).toMutableList()
    toClear.clear()
    println(toClear)
    println(toClear.isEmpty())

    // === toSet() ===
    val copiedSet = sourceList.toSet()
    println(copiedSet)
    println(copiedSet.contains(2))

    // === toMutableMap() ===
    val sourceMap = mapOf("a" to 1)
    val copiedMap = sourceMap.toMutableMap()
    copiedMap["b"] = 2
    println(sourceMap)
    println(copiedMap)

    // --- toSet() comprehensive tests ---

    // Duplicate removal
    val dupes = listOf(3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5)
    val dupesSet = dupes.toSet()
    println(dupesSet)
    println(dupesSet.size)

    // Empty list to set
    val emptySet = emptyList<Int>().toSet()
    println(emptySet)
    println(emptySet.isEmpty())
    println(emptySet.size)

    // Single element
    val singleSet = listOf(42).toSet()
    println(singleSet)
    println(singleSet.size)

    // String toSet
    val strSet = listOf("apple", "banana", "apple", "cherry", "banana").toSet()
    println(strSet)
    println(strSet.size)
    println(strSet.contains("apple"))
    println(strSet.contains("grape"))

    // Set to set (idempotent)
    val alreadySet = setOf(10, 20, 30)
    val setFromSet = alreadySet.toSet()
    println(setFromSet)
    println(setFromSet.size)

    // toMutableSet and modification
    val mutableSet = listOf(1, 2, 3, 2, 1).toMutableSet()
    mutableSet.add(4)
    mutableSet.add(2) // already present
    println(mutableSet)
    println(mutableSet.size)

    // Insertion order preserved (LinkedHashSet)
    val orderedSet = listOf(5, 3, 1, 4, 1, 5, 9).toSet()
    println(orderedSet)

    // Boolean/nullable-free contains checks
    val numSet = listOf(10, 20, 30, 40, 50).toSet()
    println(numSet.contains(30))
    println(numSet.contains(99))
}
