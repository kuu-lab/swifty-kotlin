// KUU-4456: a lambda literal passed to an overload set whose parameters are
// generic receiver functions (`Ck<T>.() -> Unit`) must adopt the chosen
// candidate's receiver so `this` members resolve, and the call must not report
// SEMA-0473 while picking the Iterable overload.
import kotlin.jvm.JvmName

sealed class Assert<out T>(val v: T)
class A2<T>(v: T) : Assert<T>(v)
class Ck<T>(val size: Int)

@JvmName("collIterable")
fun <T> Assert<Iterable<T>>.coll(check: Ck<T>.() -> Unit) = check(Ck(v.count()))
@JvmName("collSequence")
fun <T> Assert<Sequence<T>>.coll(check: Ck<T>.() -> Unit) = check(Ck(v.count()))

fun <E> Assert<Iterable<E>>.none() = coll { println("iter=$size") }
fun <E> Assert<Sequence<E>>.noneSeq() = coll { println("seq=${this.size}") }

fun main() {
    A2(listOf(1, 2, 3)).none()
    A2(sequenceOf(1, 2)).noneSeq()
}
