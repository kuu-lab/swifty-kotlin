import kotlin.sequences.*
suspend fun <T> SequenceScope<T>.twice(value: T) { yield(value); this.yield(value) }
inline fun action(block: () -> Unit) { block() }
class Owner(val n: Int) {
    suspend fun SequenceScope<Int>.member() { twice(n); yield(n + 1) }
    fun values(): Sequence<Int> = sequence { member(); this.yield(this@Owner.n + 2) }
}
inline fun <reified T> selected(values: List<Any>): Sequence<T> = sequence { for (item in values) { if (item is T) yield(item) } }
fun main() {
    println(Owner(3).values().toList())
    val f: suspend SequenceScope<Int>.() -> Unit = { yield(7) }
    println(sequence(block = f).toList()); println(iterator(block = f).asSequence().toList())
    println(sequence<Int> { f(); f(this); this.f() }.toList())
    var total = 10
    val shared = sequence { var local = 0; action { yield(total) }; listOf(1, 2).forEach { local += it; total++; yield(local + total) } }
    println(shared.toList()); println(shared.toList()); println(total)
    val left = shared.iterator(); val right = shared.iterator(); println(left.next()); println(right.next()); println(left.next()); println(right.next())
    println(selected<String>(listOf<Any>(1, "x", 2, "y")).toList())
    println(sequence<Long> { yield(4294967296L); yieldAll(listOf(9L)) }.toList())
    println(sequence<UInt> { yield(UInt.MAX_VALUE); yield(0u) }.toList())
    println(sequence<Char> { yield('界'); yieldAll("ab".asSequence()) }.joinToString())
}
