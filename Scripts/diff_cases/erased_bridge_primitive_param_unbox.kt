abstract class Acc<T> { abstract fun add(a: T, b: T): T; fun sumAll(xs: List<T>, zero: T): T { var acc = zero; for (x in xs) acc = add(acc, x); return acc } }
class DblAcc : Acc<Double>() { override fun add(a: Double, b: Double) = a + b }
class FltAcc : Acc<Float>() { override fun add(a: Float, b: Float) = a + b }
class IntAcc : Acc<Int>() { override fun add(a: Int, b: Int) = a + b }
class LongAcc : Acc<Long>() { override fun add(a: Long, b: Long) = a + b }
class ChrAcc : Acc<Char>() { override fun add(a: Char, b: Char) = if (a > b) a else b }
class BoolAcc : Acc<Boolean>() { override fun add(a: Boolean, b: Boolean) = a || b }
class ByteAcc : Acc<Byte>() { override fun add(a: Byte, b: Byte) = (a + b).toByte() }
class ShortAcc : Acc<Short>() { override fun add(a: Short, b: Short) = (a + b).toShort() }
interface Op<T> { fun combine(a: T, b: T): T }
object DblOp : Op<Double> { override fun combine(a: Double, b: Double) = a * b }
interface Sink<T> { fun accept(x: T) }
class DblSink : Sink<Double> { var total = 0.0; override fun accept(x: Double) { total += x } }
class ChrSink : Sink<Char> { var last = ' '; override fun accept(x: Char) { last = x } }
class BoolSink : Sink<Boolean> { var v = false; override fun accept(x: Boolean) { v = x } }
fun <T> fold(xs: List<T>, z: T, op: Op<T>): T { var acc = z; for (x in xs) acc = op.combine(acc, x); return acc }
fun main() {
    println(DblAcc().sumAll(listOf(0.5, 0.25), 0.0))
    println(DblAcc().add(1.5, 2.0))
    val acc: Acc<Double> = DblAcc(); println(acc.add(1.5, 2.0))
    println(FltAcc().sumAll(listOf(0.5f, 0.25f), 0.0f))
    println(IntAcc().sumAll(listOf(1, 2, 3), 0))
    println(LongAcc().sumAll(listOf(1L, 2L, 3L), 0L))
    println(ChrAcc().sumAll(listOf('a', 'z', 'c'), 'a'))
    println(BoolAcc().sumAll(listOf(false, true), false))
    println(ByteAcc().sumAll(listOf(1.toByte(), 2.toByte()), 0.toByte()))
    println(ShortAcc().sumAll(listOf(1.toShort(), 2.toShort()), 0.toShort()))
    val op: Op<Double> = DblOp; println(op.combine(1.5, 2.0))
    println(fold(listOf(2.0, 3.0), 1.0, DblOp))
    val s: Sink<Double> = DblSink(); s.accept(1.5); s.accept(2.0); println((s as DblSink).total)
    val c: Sink<Char> = ChrSink(); c.accept('q'); println((c as ChrSink).last)
    val b: Sink<Boolean> = BoolSink(); b.accept(true); println((b as BoolSink).v)
}
