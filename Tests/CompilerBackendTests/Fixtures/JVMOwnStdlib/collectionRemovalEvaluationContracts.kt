import fixture.RemovalMembershipLists
class BombHash {
    override fun hashCode(): Int {
        println("hash")
        throw IllegalArgumentException("hash")
    }
}
fun throwingKeys(): Sequence<BombHash> = sequence {
    println("yield")
    yield(BombHash())
    println("throw")
    throw IllegalStateException("rhs")
}
fun report(name: String, body: () -> Int) {
    println(name)
    try { println(body()) }
    catch (e: IllegalStateException) { println("caught rhs") }
    catch (e: IllegalArgumentException) { println("caught hash") }
}
fun main() {
    report("set sequence failure") { (emptySet<BombHash>() - throwingKeys()).size }
    report("map sequence failure") { (emptyMap<BombHash, Int>() - throwingKeys()).size }
    report("empty set array") { (emptySet<BombHash>() - arrayOf(BombHash())).size }
    report("empty map array") { (emptyMap<BombHash, Int>() - arrayOf(BombHash())).size }
    report("empty set sequence") { (emptySet<BombHash>() - sequenceOf(BombHash())).size }
    report("empty map sequence") { (emptyMap<BombHash, Int>() - sequenceOf(BombHash())).size }
    report("set receiver first") { (setOf(BombHash()) - throwingKeys()).size }
    report("map receiver first") { (mapOf(BombHash() to 1) - throwingKeys()).size }
    report("set empty iterable") { (setOf(BombHash()) - emptyList<BombHash>()).size }
    val source = setOf("A", "B")
    val map = mapOf("A" to 1, "B" to 2)
    val small = RemovalMembershipLists.rhs(1) as Collection<String>
    val equal = RemovalMembershipLists.rhs(2) as Collection<String>
    val large = RemovalMembershipLists.rhs(3) as Collection<String>
    println("set small"); println(source - small)
    println("set equal"); println(source - equal)
    println("set large"); println(source - large)
    println("map small"); println(map - small)
    println("map equal"); println(map - equal)
    println("map large"); println(map - large)
    println(source); println(map)
}
