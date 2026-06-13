// Function parameter type
fun processLinkedSet(set: LinkedHashSet<String>) {
    println(set.size)
}

// Return type
fun createLinkedSet(): LinkedHashSet<Int> {
    return LinkedHashSet<Int>()
}

// Property type
class OrderedTags {
    val tags: LinkedHashSet<String> = LinkedHashSet()
    val ids: LinkedHashSet<Int> = LinkedHashSet<Int>()
}

// Generic type argument
fun nestedLinkedSets() {
    val nested: LinkedHashSet<LinkedHashSet<String>> = LinkedHashSet()
    val inner = LinkedHashSet<String>()
    inner.add("nested")
    nested.add(inner)
    println(nested.size)
}

// Inheritance
class MySet : LinkedHashSet<String>() {
    fun customOp() = "custom"
}

// Type constraint
fun <T : LinkedHashSet<String>> constrainLinked(set: T): T {
    return set
}

// Extension function on LinkedHashSet
fun LinkedHashSet<String>.linkedExtension(): String {
    return "linked: ${this.size}"
}

fun main() {
    val set: LinkedHashSet<String> = LinkedHashSet()
    set.add("hello")
    set.add("world")
    println(set.size)
    println(set.contains("hello"))

    val ms: MutableSet<String> = set
    ms.add("!")
    println(ms.size)

    val ordered = linkedSetOf(1, 2, 3)
    ordered.remove(2)
    println(ordered.size)

    val readOnly: Set<String> = set
    println(readOnly.size)

    processLinkedSet(set)

    val created = createLinkedSet()
    created.add(42)
    println(created.size)

    val container = OrderedTags()
    container.tags.add("property")
    println(container.tags.size)

    nestedLinkedSets()

    val mySet = MySet()
    mySet.add("inherited")
    println(mySet.customOp())

    val constrained = constrainLinked(set)
    println(constrained.size)

    println(set.linkedExtension())
}
