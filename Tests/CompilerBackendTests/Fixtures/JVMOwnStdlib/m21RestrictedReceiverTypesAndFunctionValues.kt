import kotlin.sequences.*
import kotlin.sequences.sequence
import kotlin.sequences.iterator
import kotlin.sequences.sequence as seq
import kotlin.sequences.iterator as iter
suspend fun <S: SequenceScope<Int>> S.genericYield() { yield(10) }
suspend fun forward(f: suspend SequenceScope<Int>.() -> Unit, scope: SequenceScope<Int>) { f(scope) }
suspend fun SequenceScope<Int>?.nullableSmart() { if (this != null) yield(2) }
@JvmInline value class Id(val value: Int)
fun main() {
    val f: suspend SequenceScope<Int>.() -> Unit = { yield(7) }
    val delegated: suspend SequenceScope<Int>.() -> Unit = { val alias = this; f(alias); this.f() }
    println(sequence(block = delegated).toList())
    println(sequence<Int> { nullableSmart(); genericYield() }.toList())
    val values = sequence { yieldAll(listOf(1, 2)); yieldAll(sequenceOf(3)) }; println(values.toList())
    println(iterator { yieldAll(listOf("x", "y")) }.asSequence().toList())
    println(seq { yieldAll(listOf(5, 6)) }.toList()); println(iter { yieldAll(listOf(7, 8)) }.asSequence().toList())
    println(kotlin.sequences.sequence { yieldAll(listOf(9)) }.toList()); println(kotlin.sequences.iterator { yieldAll(listOf(10)) }.asSequence().toList())
    println(sequence<Int> { buildString { yield(11); append("x") }; yield(12) }.toList())
    println(iter<Int> { yield(13); return@iter }.asSequence().toList())
    println(sequence<Id> { yield(Id(1)); yieldAll(listOf(Id(2))) }.map { it.value }.toList())
    println(sequence { yield(intArrayOf(3)); yieldAll(listOf(intArrayOf(4))) }.map { it[0] }.toList())
}
