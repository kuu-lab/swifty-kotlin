package golden.sema

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

fun contextGet(ctx: CoroutineContext, key: CoroutineContext.Key<CoroutineContext.Element>): CoroutineContext.Element? =
    ctx.get(key)

fun contextGetIndexed(ctx: CoroutineContext, key: CoroutineContext.Key<CoroutineContext.Element>): CoroutineContext.Element? =
    ctx[key]

fun contextFold(ctx: CoroutineContext): Int =
    ctx.fold(7) { acc, _ -> acc + 1 }

fun contextMinusKey(ctx: CoroutineContext, key: CoroutineContext.Key<*>): CoroutineContext =
    ctx.minusKey(key)

fun contextPlus(ctx: CoroutineContext, other: CoroutineContext): CoroutineContext =
    ctx + other

fun contextPlusDirect(ctx: CoroutineContext, other: CoroutineContext): CoroutineContext =
    ctx.plus(other)

fun main() {
    val ctx: CoroutineContext = EmptyCoroutineContext
    println(contextFold(ctx))
    println(contextPlus(ctx, ctx) === ctx)
}
