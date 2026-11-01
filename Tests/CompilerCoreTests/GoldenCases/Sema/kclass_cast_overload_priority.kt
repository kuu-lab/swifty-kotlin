// KUU-4046: kotlin.reflect cast/safeCast/createInstance carry
// @LowPriorityInOverloadResolution so the kotlin.reflect.full overloads win
// when both bundled packages surface the same KClass extension unqualified.
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
