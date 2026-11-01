// KUU-4046: kotlin.reflect cast/safeCast/createInstance carry
// @LowPriorityInOverloadResolution. KUU-4070 then gated kotlin.reflect.full
// behind explicit imports, so unqualified member calls like these bind the
// kotlin.reflect shims unambiguously (full.* is not surfaced at all).
package golden.sema

import kotlin.reflect.KClass

class Box(val value: Int = 3)

fun <T : Any> castVia(klass: KClass<T>, value: Any?): T = klass.cast(value)

fun <T : Any> safeCastVia(klass: KClass<T>, value: Any?): T? = klass.safeCast(value)

fun makeBox(k: KClass<Box>): Box = k.createInstance()

fun inspect(k: KClass<*>) {
    println(k.cast(42))
    println(k.safeCast("other"))
}
