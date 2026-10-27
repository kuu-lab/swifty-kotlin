// KUU-3534 / KUU-3176: `x as (T & Any)` on a null operand throws a catchable
// NullPointerException (Kotlin/JVM semantics), not a ClassCastException and
// never a trap. The same rule covers erased `as T` casts whose only runtime
// contract is non-nullness.
fun <T> test(t: T) = t as (T & Any)

fun <T : CharSequence?> castWithUpperBound(v: T) = v as (T & Any)

fun <T : Any> strict(value: Any?): T = value as T

fun <U : Any, T : U> dependent(value: Any?): T = value as T

fun <T> safeTest(t: T) = t as? (T & Any)

fun main() {
    // Null operand -> catchable NPE.
    println(try { test<Any?>(null); "FAIL" } catch (ex: NullPointerException) { "OK" })
    println(try { castWithUpperBound<CharSequence?>(null); "FAIL" } catch (ex: NullPointerException) { "OK" })
    println(try { strict<String>(null); "FAIL" } catch (ex: NullPointerException) { "OK" })
    println(try { dependent<Any, String>(null); "FAIL" } catch (ex: NullPointerException) { "OK" })

    // The thrown type really is NPE (class-name independent check).
    println(try { test<Any?>(null); "FAIL" } catch (ex: Throwable) { ex is NullPointerException })
    println(try { test<Any?>(null); "FAIL" } catch (ex: Throwable) { ex is ClassCastException })

    // Non-null operands pass through unchanged.
    println(test<Any?>("value"))
    println(castWithUpperBound<CharSequence?>("seq"))
    println(strict<String>("strict-ok"))

    // Safe casts keep null instead of throwing.
    println(safeTest<Any?>(null) == null)
    println(safeTest<Any?>("safe") != null)

    // Unbounded `as T` still admits null.
    fun <T> plain(t: T) = t as T
    println(plain<Any?>(null) == null)
}
