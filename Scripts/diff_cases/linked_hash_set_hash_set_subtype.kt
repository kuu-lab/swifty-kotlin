// KUU-1940: LinkedHashSet is a distinct HashSet subclass.
fun main() {
    val lhs = LinkedHashSet<Int>()
    lhs.add(1)
    println(lhs is HashSet<Int>)
    val viaSub: HashSet<Int> = lhs
    println(viaSub.size)

    val erased: Any = lhs
    println(erased is HashSet<*>)
    println(erased is MutableSet<*>)
    println(erased is Set<*>)
    val cast = erased as HashSet<Int>
    cast.add(2)
    println(lhs.joinToString())

    val plain: Any = HashSet<Int>()
    println(plain is LinkedHashSet<*>)
    println(plain as? LinkedHashSet<Int> == null)

    val capacity: HashSet<Int> = LinkedHashSet<Int>(8)
    capacity.add(3)
    println(capacity.size)
    val copy: HashSet<Int> = LinkedHashSet(listOf(3, 1, 3))
    println(copy.joinToString())

    val factory: Any = linkedSetOf(4, 2, 4)
    println(factory is HashSet<*>)
    val mutableFactory: Any = mutableSetOf(5, 2)
    println(mutableFactory is HashSet<*>)
}
