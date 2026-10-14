import java.util.LinkedList

fun unitTail(q: LinkedList<Unit>): Unit = q.peekLast()
fun unitTailBlock(q: LinkedList<Unit>): Unit { return q.peekLast() }
fun unitLocalReturn(q: LinkedList<Unit>): Unit {
    val value: Unit = q.peekLast()
    return value
}
fun takeUnit(value: Unit) { println(value) }
fun <T> identity(value: T): T = value
fun <T : Any> boundedIdentity(value: T): T = value
fun Unit.consume() { println("called") }
class UnitHolder(val q: LinkedList<Unit>) {
    val stored: Unit = q.peekLast()
    val explicit: Unit get() = q.peekLast()
    val block: Unit get() { return q.peekLast() }
}

fun observeProperties(holder: UnitHolder?) {
    println(holder?.stored)
    println(holder?.explicit)
    println(holder?.block)
}

fun main() {
    val q = LinkedList<Unit>(); q.add(Unit); val value: Unit = q.peekLast(); println(value)
    println("size:${q.size}")
    println(unitTail(q))
    takeUnit(q.peekLast())
    val present: Unit? = q.peekLast()
    println(present)
    q.clear()
    val absent: Unit? = q.peekLast()
    println(absent)
    println(q.peekLast())
    try { val nonNull: Unit = q.peekLast(); println(nonNull) }
    catch (e: NullPointerException) { println("npe:local") }
    try { println(unitTail(q)) }
    catch (e: NullPointerException) { println("npe:return") }
    println(unitTailBlock(q))
    println(unitLocalReturn(q))
    fun localTail(): Unit = q.peekLast()
    println(localTail())
    val unitCallback: () -> Unit = { q.peekLast() }
    println(unitCallback())
    try { takeUnit(q.peekLast()) }
    catch (e: NullPointerException) { println("npe:argument") }
    val local: Unit = q.peekLast()
    println(identity(local))
    println(identity<Unit?>(local))
    try { println(boundedIdentity(local)) }
    catch (e: NullPointerException) { println("npe:bounded-argument") }
    try { takeUnit(local) }
    catch (e: NullPointerException) { println("npe:local-argument") }
    val callback: (Unit) -> Unit = { println(it) }
    try { callback(q.peekLast()) }
    catch (e: NullPointerException) { println("npe:function") }
    try { local.consume() }
    catch (e: NullPointerException) { println("npe:receiver") }
    val receiverCallback: Unit.() -> Unit = { println("called") }
    try { receiverCallback(q.peekLast()) }
    catch (e: NullPointerException) { println("npe:function-receiver") }
    println(q.peekLast()?.receiverCallback())
    val holder = UnitHolder(q)
    println(holder.stored)
    println(holder.explicit)
    println(holder.block)
    observeProperties(holder)
    observeProperties(null)
    val nullable = LinkedList<Unit?>()
    nullable.add(null)
    println(nullable.peekLast())
    nullable.add(Unit)
    println(nullable.peekLast())
    val receiver: LinkedList<Unit>? = null
    println(receiver?.peekLast())
}
