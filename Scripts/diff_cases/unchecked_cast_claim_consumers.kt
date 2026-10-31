// KUU-3893: a non-reified generic result crosses the call boundary in erased
// form, and Kotlin/JVM claims it (checkcast) only where the substituted type
// is actually required — raw consumers like `!=`/`==`/`===`, `is`/`as`,
// `!!`, `throw`, string templates, and discarded statements never claim,
// while `when` subjects and declared-typed destinations still do.
interface I1
interface I2
open class C {
    override fun toString(): String = "C"
}
class CI1I2 : C(), I1, I2 {
    override fun toString(): String = "CI1I2"
}
class OtherCI1I2 : C(), I1, I2

fun <R : C> Any?.uncheckedCast(): R where R : I1, R : I2 = this as R
fun <R : C> Any?.uncheckedSafeCast(): R? where R : I1, R : I2 = this as? R
fun <T : Throwable> Any?.uncheckedCastThrowable(): T = this as T
fun takeAny(x: Any?): Boolean = x is CI1I2
fun <T : C?> takeTyped(x: T): Boolean = x is CI1I2

fun main() {
    // An erased result consumed at Any? survives uncast (heap pollution).
    val raw: Any? = CI1I2().uncheckedSafeCast<OtherCI1I2>()
    // Equality and identity consume the raw erased value.
    println("ne:${CI1I2().uncheckedSafeCast<OtherCI1I2>() != null}")
    println("eq-null:${CI1I2().uncheckedSafeCast<OtherCI1I2>() == null}")
    println("id-eq-self:${CI1I2().uncheckedSafeCast<OtherCI1I2>() === (CI1I2() as C)}")
    println("id-ne-null:${CI1I2().uncheckedSafeCast<OtherCI1I2>() !== null}")
    println("eq-other:${CI1I2().uncheckedSafeCast<OtherCI1I2>() == OtherCI1I2()}")
    // `is` checks the runtime class on the raw value; a same-nominal
    // claim-type check folds to a null check, supertype targets keep a real
    // instanceof, and nullable targets keep `x == null || x instanceof T`.
    println("is-claimed:${CI1I2().uncheckedSafeCast<OtherCI1I2>() is OtherCI1I2}")
    println("is-ci:${raw is CI1I2}")
    println("is-c:${CI1I2().uncheckedSafeCast<OtherCI1I2>() is C}")
    println("is-i1:${CI1I2().uncheckedSafeCast<OtherCI1I2>() is I1}")
    println("not-is-claimed:${CI1I2().uncheckedSafeCast<OtherCI1I2>() !is OtherCI1I2}")
    println("is-claimed-nullable:${CI1I2().uncheckedSafeCast<OtherCI1I2>() is OtherCI1I2?}")
    println("is-c-nullable:${CI1I2().uncheckedSafeCast<OtherCI1I2>() is C?}")
    println("null-is-nullable:${(null as Any?).uncheckedSafeCast<OtherCI1I2>() is OtherCI1I2?}")
    // `as`/`as?` run their own cast against the claim type.
    println(try { CI1I2().uncheckedSafeCast<OtherCI1I2>() as OtherCI1I2; "as-ok" } catch (e: ClassCastException) { "as:CCE" })
    println("safe-as-claimed:${CI1I2().uncheckedSafeCast<OtherCI1I2>() as? OtherCI1I2 == null}")
    println("safe-as-c:${(CI1I2().uncheckedSafeCast<OtherCI1I2>() as? C) != null}")
    // `!!` asserts null only, then the member call dispatches the raw value.
    println("bang:${(CI1I2().uncheckedSafeCast<OtherCI1I2>())!!.toString()}")
    // String templates append the raw value.
    println("template:${CI1I2().uncheckedSafeCast<OtherCI1I2>()}")
    // `throw` consumes the erased value directly.
    println(try { throw (RuntimeException().uncheckedCastThrowable<AssertionError>()) } catch (e: ClassCastException) { "claim-cce" } catch (e: RuntimeException) { "thrown-re" } catch (e: AssertionError) { "thrown-ae" })
    // A `when` subject still claims into its synthetic typed local.
    println(try { when (CI1I2().uncheckedSafeCast<OtherCI1I2>()) { is C -> "when-c"; else -> "when-else" } } catch (e: ClassCastException) { "when:CCE" })
    // Declared-type and erased-parameter consumers still claim.
    println(try { val t: OtherCI1I2? = CI1I2().uncheckedSafeCast<OtherCI1I2>(); "typed-ok" } catch (e: ClassCastException) { "typed:CCE" })
    println("typed-arg:${takeTyped<OtherCI1I2?>(CI1I2().uncheckedSafeCast<OtherCI1I2>())}")
    println("any-arg:${takeAny(CI1I2().uncheckedSafeCast<OtherCI1I2>())}")
    println("raw-is-ci:${raw is CI1I2}")
    println("raw-ne:${raw != null}")
    // Discarded statements do not claim.
    CI1I2().uncheckedCast<OtherCI1I2>()
    println("stmt-ok")
}
