// KSP-1324: kotlin.reflect KClass cast / safeCast / findAssociatedObject.
package golden.sema

import kotlin.reflect.ExperimentalAssociatedObjects
import kotlin.reflect.KClass
import kotlin.reflect.cast
import kotlin.reflect.findAssociatedObject
import kotlin.reflect.safeCast

annotation class Binding

class Box(val value: Int)

fun <T : Any> castVia(klass: KClass<T>, value: Any?): T = klass.cast(value)

fun <T : Any> safeCastVia(klass: KClass<T>, value: Any?): T? = klass.safeCast(value)

@OptIn(ExperimentalAssociatedObjects::class)
fun findBinding(kclass: KClass<*>): Any? = kclass.findAssociatedObject<Binding>()
