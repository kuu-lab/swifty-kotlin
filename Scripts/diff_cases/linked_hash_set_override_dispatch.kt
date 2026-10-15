class CustomSet : LinkedHashSet<Int>() {
    override val size: Int
        get() = 42
    override fun contains(element: Int): Boolean = true
}
class PlainHashSet : HashSet<Int>()

fun probeLinked(value: LinkedHashSet<Int>) {
    println(value.size)
    println(value.contains(999))
}

fun probeHash(value: HashSet<Int>) {
    println(value.size)
    println(value.contains(999))
}

fun probeMutable(value: MutableSet<Int>) {
    println(value.size)
    println(value.contains(999))
}

fun main() {
    val custom = CustomSet()
    probeLinked(custom)
    probeHash(custom)
    probeMutable(custom)

    val plainHash = PlainHashSet()
    plainHash.add(1)
    probeHash(plainHash)

    val linked: LinkedHashSet<Int> = LinkedHashSet()
    linked.add(1)
    println(linked.size)
    println(linked.contains(1))

    val hash: HashSet<Int> = HashSet()
    hash.add(1)
    println(hash.size)
    println(hash.contains(1))

    val mutable: MutableSet<Int> = mutableSetOf(1)
    println(mutable.size)
    println(mutable.contains(1))
}
