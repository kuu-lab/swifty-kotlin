/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the license/LICENSE.txt file.
 */

package kotlin

import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn
import kotlin.jvm.internal.__jvmResultValue
import kotlin.jvm.internal.__jvmResume

@SinceKotlin("1.7")
public class DeepRecursiveFunction<T, R>(
    internal val block: suspend DeepRecursiveScope<T, R>.(T) -> R
)

@SinceKotlin("1.7")
public operator fun <T, R> DeepRecursiveFunction<T, R>.invoke(value: T): R =
    DeepRecursiveScopeImpl(block, value).runCallLoop()

@RestrictsSuspension
@SinceKotlin("1.7")
@WasExperimental(ExperimentalStdlibApi::class)
public sealed class DeepRecursiveScope<T, R> {
    public abstract suspend fun callRecursive(value: T): R

    public abstract suspend fun <U, S> DeepRecursiveFunction<U, S>.callRecursive(value: U): S

    @Deprecated(
        level = DeprecationLevel.ERROR,
        message = "'invoke' should not be called from DeepRecursiveScope. Use 'callRecursive' to do recursion in the heap instead of the call stack.",
        replaceWith = ReplaceWith("this.callRecursive(value)")
    )
    @Suppress("UNUSED_PARAMETER")
    public operator fun DeepRecursiveFunction<*, *>.invoke(value: Any?): Nothing =
        throw UnsupportedOperationException("Should not be called from DeepRecursiveScope")
}

private typealias DeepRecursiveFunctionBlock = suspend DeepRecursiveScope<*, *>.(Any?) -> Any?

private object UndefinedDeepRecursiveResult

private val UNDEFINED_RESULT: Any = UndefinedDeepRecursiveResult

@Suppress("UNCHECKED_CAST")
private class DeepRecursiveScopeImpl<T, R>(
    block: suspend DeepRecursiveScope<T, R>.(T) -> R,
    value: T
) : DeepRecursiveScope<T, R>(), Continuation<R> {
    private var function: DeepRecursiveFunctionBlock = block as DeepRecursiveFunctionBlock
    private var value: Any? = value
    private var cont: Continuation<Any?>? = this as Continuation<Any?>
    private var result: Any? = UNDEFINED_RESULT

    override val context: CoroutineContext
        get() = EmptyCoroutineContext

    override fun resumeWith(result: Result<R>) {
        cont = null
        this.result = __jvmResultValue(result)
    }

    override suspend fun callRecursive(value: T): R = suspendCoroutineUninterceptedOrReturn { continuation ->
        cont = continuation as Continuation<Any?>
        this.value = value
        COROUTINE_SUSPENDED
    }

    override suspend fun <U, S> DeepRecursiveFunction<U, S>.callRecursive(value: U): S = suspendCoroutineUninterceptedOrReturn { continuation ->
        val nextFunction = block as DeepRecursiveFunctionBlock
        val currentFunction = function
        if (nextFunction !== currentFunction) {
            function = nextFunction
            cont = crossFunctionCompletion(currentFunction, continuation as Continuation<Any?>)
        } else {
            cont = continuation as Continuation<Any?>
        }
        this@DeepRecursiveScopeImpl.value = value
        COROUTINE_SUSPENDED
    }

    private fun crossFunctionCompletion(
        currentFunction: DeepRecursiveFunctionBlock,
        continuation: Continuation<Any?>
    ): Continuation<Any?> = object : Continuation<Any?> {
        override val context: CoroutineContext
            get() = EmptyCoroutineContext

        override fun resumeWith(result: Result<Any?>) {
            function = currentFunction
            cont = continuation
            this@DeepRecursiveScopeImpl.result = __jvmResultValue(result)
        }
    }

    @Suppress("UNCHECKED_CAST")
    fun runCallLoop(): R {
        while (true) {
            val currentResult = result
            val currentCont = cont ?: run {
                kotlin.throwOnFailure(currentResult)
                return currentResult as R
            }
            if (UNDEFINED_RESULT === currentResult) {
                val outcome = try {
                    val callback = function as (DeepRecursiveScope<*, *>, Any?, Continuation<Any?>) -> Any?
                    callback(this, value, currentCont)
                } catch (failure: Throwable) {
                    currentCont.resumeWithException(failure)
                    continue
                }
                if (outcome !== COROUTINE_SUSPENDED) currentCont.resume(outcome as R)
            } else {
                result = UNDEFINED_RESULT
                __jvmResume(currentCont, currentResult)
            }
        }
    }
}
