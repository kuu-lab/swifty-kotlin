// KSP-704: source-backed LinkedHashSet constructors and MutableSet defaults.

class OrderedTags : LinkedHashSet<String>()

fun main() {
    val values = LinkedHashSet<Int>()
    values.add(1)
    values.add(1)
    values.add(2)

    val sized = LinkedHashSet<Int>(8)
    sized.add(3)
    println(sized.size)

    val copied = LinkedHashSet(listOf(4, 5, 4))
    copied += 6
    copied += listOf(7, 8)
    copied -= 4
    copied -= listOf(8, 9)
    println(copied)
    println(copied.removeAll(listOf(5, 9)))
    println(copied.retainAll(listOf(6, 7)))
    println(copied)
    println(copied.isEmpty())

    val subclass = OrderedTags()
    subclass.add("kotlin")
    subclass.add("swift")
    println(subclass.size)
    println(subclass.contains("kotlin"))
    subclass.clear()
    println(subclass.isEmpty())

    println(values)
    println(values is LinkedHashSet<*>)
    println(values is MutableSet<*>)
}
