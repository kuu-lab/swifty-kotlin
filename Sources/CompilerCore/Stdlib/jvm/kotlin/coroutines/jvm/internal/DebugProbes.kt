@file:kotlin.jvm.JvmName("DebugProbesKt")
package kotlin.coroutines.jvm.internal
fun <T> probeCoroutineCreated(completion: kotlin.coroutines.Continuation<T>): kotlin.coroutines.Continuation<T> = completion
fun probeCoroutineResumed(frame: kotlin.coroutines.Continuation<*>) {}
fun probeCoroutineSuspended(frame: kotlin.coroutines.Continuation<*>) {}
