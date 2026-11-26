package kotlinx.coroutines.intrinsics

import kotlin.coroutines.Continuation
import kotlin.internal.KsSymbolName
import kotlinx.coroutines.InternalCoroutinesApi

@KsSymbolName("__kk_start_coroutine_cancellable")
@InternalCoroutinesApi
@SinceKotlin("1.3")
public external fun <T> (suspend () -> T).startCoroutineCancellable(completion: Continuation<T>)
