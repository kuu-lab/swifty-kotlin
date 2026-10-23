// KUU-2958: an unchecked cast to a type parameter with multiple upper bounds
// checkcasts against the first upper bound (the erasure), like Kotlin/JVM —
// so an incompatible value throws a catchable ClassCastException.
interface I1
interface I2
open class C
class CI1I2 : C(), I1, I2
class OtherCI1I2 : C(), I1, I2
class Unrelated

fun <R : C> Any?.uncheckedCast(): R where R : I1, R : I2 = this as R
fun <R : C> Any?.uncheckedSafeCast(): R? where R : I1, R : I2 = this as? R
fun <R : C> Any?.nullableTarget(): R? where R : I1, R : I2 = this as R?
fun <U : C, T : U> Any?.transitiveCast(): T = this as T

fun main() {
    CI1I2().uncheckedCast<CI1I2>()
    CI1I2().uncheckedCast<OtherCI1I2>()
    println("exact/other-bound-ok")
    println(try { Any().uncheckedCast<CI1I2>(); "NO_THROW" } catch (e: ClassCastException) { "CCE" })
    println(try { Unrelated().uncheckedCast<CI1I2>(); "NO_THROW" } catch (e: ClassCastException) { "CCE" })
    println(Any().uncheckedSafeCast<CI1I2>() == null)
    println(CI1I2().uncheckedSafeCast<OtherCI1I2>() != null)
    println((null as Any?).uncheckedSafeCast<CI1I2>() == null)
    println(try { (null as Any?).uncheckedCast<CI1I2>(); "NO_THROW" } catch (e: NullPointerException) { "NPE" })
    println((null as Any?).nullableTarget<CI1I2>() == null)
    println(try { Any().transitiveCast<C, CI1I2>(); "NO_THROW" } catch (e: ClassCastException) { "CCE" })
    // The erasure check only sees C, so this returns a CI1I2 instance
    // typed as OtherCI1I2 — unchecked-cast semantics on the JVM too.
    val leaked: Any = CI1I2().transitiveCast<C, OtherCI1I2>()
    println(leaked is CI1I2)
}
