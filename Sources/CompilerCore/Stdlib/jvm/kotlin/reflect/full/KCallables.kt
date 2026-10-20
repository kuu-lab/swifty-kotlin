@file:kotlin.jvm.JvmName("KCallables")
package kotlin.reflect.full
import kotlin.reflect.*
import kotlin.reflect.jvm.internal.RuntimeFunction
import kotlin.coroutines.Continuation
fun callSuspend(callable: KCallable<*>, args: Array<out Any?>, continuation: Continuation<Any?>): Any? = (callable as RuntimeFunction).callSuspending(args, continuation)
