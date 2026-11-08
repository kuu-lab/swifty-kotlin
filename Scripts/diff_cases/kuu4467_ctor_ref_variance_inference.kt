// KUU-4467: a generic constructor reference `::Byp` whose class supertype
// arguments contain variance annotations and `Nothing` literals must defer
// to the enclosing generic call's inference instead of failing target
// selection with TYPE-0001 (MVIKotlin `executorFactory = ::BypassExecutor`).
interface Ex<in I : Any, in A : Any, in S : Any, out M : Any, out L : Any>
private class Byp<I : Any, in S : Any> : Ex<I, Nothing, S, I, Nothing>

interface SF {
    fun <I : Any, A : Any, S : Any, M : Any, L : Any> create(
        name: String? = null,
        ef: () -> Ex<I, A, S, M, L>
    ): Boolean = ef() is Byp<*, *>
}

class Impl : SF

fun <I : Any, S : Any> SF.c2(s: S): Boolean = create(ef = ::Byp)
fun <I : Any, S : Any> SF.c3(s: S): Boolean = create<I, Nothing, S, I, Nothing>(ef = ::Byp)

fun main() {
    val sf = Impl()
    println(sf.c2<Any, String>("x"))
    println(sf.c3<Any, String>("y"))
}
