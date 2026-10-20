package kotlin.coroutines.jvm.internal
import kotlin.coroutines.*
import kotlin.jvm.internal.FunctionBase
abstract class SuspendLambda(override val arity: Int, completion: Continuation<Any?>?): ContinuationImpl(completion), FunctionBase<Any?>, SuspendFunction {
    constructor(arity: Int): this(arity, null)
}
abstract class RestrictedSuspendLambda(override val arity: Int, completion: Continuation<Any?>?): RestrictedContinuationImpl(completion), FunctionBase<Any?>, SuspendFunction {
    constructor(arity: Int): this(arity, null)
}
