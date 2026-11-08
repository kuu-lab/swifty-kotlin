// KUU-4362: member reads through the same star-projected receiver share one
// captured type, so `ctx.type` and `ctx.value` can both drive inference for
// the same type parameter (Kodein-DI `DI.Key(ctx.anyType, ..., ctx.value)`).
interface TT<T>
interface Ctx<C : Any> { val type: TT<in C>; val value: C }
interface Cont { fun <C : Any> f(t: TT<in C>, v: C): C }

fun g(cont: Cont, ctx: Ctx<*>): Any = cont.f(ctx.type, ctx.value)

class TTI<T>(val tag: String) : TT<T>
class CtxI<C : Any>(override val type: TT<in C>, override val value: C) : Ctx<C>
class ContI : Cont { override fun <C : Any> f(t: TT<in C>, v: C): C = v }

fun main() { println(g(ContI(), CtxI(TTI("x"), 42))) }
