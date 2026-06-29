fun processSet(set: HashSet<String>) {
    println(set.size)
}

fun createSet(): HashSet<Int> {
    return hashSetOf<Int>()
}

class TagContainer {
    val tags: HashSet<String> = hashSetOf()
    val ids: HashSet<Int> = hashSetOf<Int>()
}

fun nestedSets() {
    val nested: HashSet<HashSet<String>> = hashSetOf()
    val inner = hashSetOf<String>()
    inner.add("nested")
    nested.add(inner)
    println(nested.size)
}

fun <T : HashSet<String>> constrain(set: T): T {
    return set
}

fun HashSet<String>.customExtension(): String {
    return "extended: ${this.size}"
}

fun main() {
    val set: HashSet<String> = hashSetOf()
    set.add("hello")
    set.add("world")
    println(set.size)
    println(set.contains("hello"))

    val ms: MutableSet<String> = set
    ms.add("!")
    println(ms.size)

    val nums = hashSetOf(1, 2, 3)
    nums.remove(2)
    println(nums.size)

    val readOnly: Set<String> = set
    println(readOnly.size)

    processSet(set)

    val created = createSet()
    created.add(42)
    println(created.size)

    val container = TagContainer()
    container.tags.add("property")
    println(container.tags.size)

    nestedSets()

    val constrained = constrain(set)
    println(constrained.size)

    println(set.customExtension())
}
