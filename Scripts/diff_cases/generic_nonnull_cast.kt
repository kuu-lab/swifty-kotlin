// KUU-2387: erased casts retain the non-null upper-bound contract.
fun <T : Any> strict(value: Any?): T = value as T
fun <T : Any> explicitNullable(value: Any?): T? = value as T?
fun <T> unconstrained(value: Any?): T = value as T
fun <T : Any?> nullableBound(value: Any?): T = value as T
fun <T : Any> safeStrict(value: Any?): T? = value as? T
fun <T : Any?> safeNullable(value: Any?): T? = value as? T
fun <U : Any, T : U> dependent(value: Any?): T = value as T
fun <U, T : U> nullableDependent(value: Any?): T = value as T
inline fun <reified T : Any> reifiedStrict(value: Any?): T = value as T
inline fun <reified T : Any> reifiedExplicitNullable(value: Any?): T? = value as T?
inline fun <reified T : Any?> reifiedNullable(value: Any?): T = value as T
inline fun <reified T : Any> reifiedSafe(value: Any?): T? = value as? T
inline fun <reified T : Any?> reifiedSafeNullable(value: Any?): T? = value as? T

fun <T : Any> valueControl(value: T): T = value as T
inline fun <T : Any> inlineValueControl(value: T): T = value as T
fun <T> definitelyNotNull(value: T) = value as (T & Any)

fun main() {
    println(try { definitelyNotNull<Any?>(null); "FAIL" } catch (e: NullPointerException) { definitelyNotNull("OK") })
    println(definitelyNotNull("OK"))
    println(try { strict<String>(null); "NO_THROW" } catch (e: NullPointerException) { "NPE" })
    println(explicitNullable<String>(null) == null)
    println(unconstrained<String?>(null) == null)
    println(nullableBound<String?>(null) == null)
    println(safeStrict<String>(null) == null)
    println(safeNullable<String?>(null) == null)
    println(try { dependent<Any, String>(null); "NO_THROW" } catch (e: NullPointerException) { "NPE" })
    println(nullableDependent<Any?, String?>(null) == null)
    println(try { reifiedStrict<String>(null); "NO_THROW" } catch (e: NullPointerException) { "NPE" })
    println(reifiedExplicitNullable<String>(null) == null)
    println(reifiedNullable<String?>(null) == null)
    println(reifiedSafe<String>(null) == null)
    println(reifiedSafeNullable<String?>(null) == null)
    println(try { reifiedNullable<String>(null); "NO_THROW" } catch (e: NullPointerException) { "NPE" })
    println(strict<String>("OK"))
    println(explicitNullable<String>("OK"))
    println(unconstrained<String>("OK"))
    println(nullableBound<String>("OK"))
    println(safeStrict<String>("OK"))
    println(safeNullable<String>("OK"))
    println(dependent<Any, String>("OK"))
    println(nullableDependent<Any?, String>("OK"))
    println(reifiedStrict<String>("OK"))
    println(reifiedExplicitNullable<String>("OK"))
    println(reifiedNullable<String>("OK"))
    println(reifiedSafe<String>("OK"))
    println(reifiedSafeNullable<String>("OK"))
    println(valueControl("OK"))
    println(inlineValueControl("OK"))
    println(valueControl(Long.MIN_VALUE))
    println(inlineValueControl(Long.MIN_VALUE))
    println(valueControl(false))
    println(inlineValueControl(false))
    println(valueControl(0))
    println(inlineValueControl(0))
    println(valueControl(-0.0).toRawBits() == Long.MIN_VALUE)
    println(inlineValueControl(-0.0).toRawBits() == Long.MIN_VALUE)
    println(valueControl(9223372036854775808uL) == 9223372036854775808uL)
    println(inlineValueControl(9223372036854775808uL) == 9223372036854775808uL)
    println(strict<Long>(Long.MIN_VALUE) == Long.MIN_VALUE)
}
