// An enum value widened to an interface must dispatch interface *methods*
// through its itable: entry-body overrides (via the ordinal-switching entry
// dispatch helper), enum-body overrides reading constructor properties,
// interface default methods, and every widening path -- assignment, call
// argument, return, collection element, inline-function / lambda parameter,
// callable reference, and a direct default-method call on the enum value.
interface I { fun f(): Int }
interface J {
    fun g(x: Int): String
    fun h(): String = "h:" + g(0)
}

enum class E : I {
    A { override fun f() = 1 },
    B { override fun f() = 2 },
}

enum class F(val k: Int) : I {
    X(5), Y(7);
    override fun f() = k + 1
}

enum class G(val k: Int) : I, J {
    P(5) { override fun f() = k + 10 },
    Q(9) {
        override fun f() = k * 2
        override fun h() = "Q-h"
    };
    override fun f() = -1
    override fun g(x: Int) = "$name:${k + x}"
}

fun use(i: I) = i.f()
fun pick(b: Boolean): I = if (b) E.B else G.P
fun call(fn: (I) -> Int, x: I) = fn(x)

fun main() {
    val i: I = E.B
    println(i.f())
    val j: I = F.X
    println(j.f())

    println(listOf<I>(E.A, E.B, F.X, F.Y, G.P, G.Q).map { it.f() })
    println(use(G.P))
    println(pick(true).f())
    println(pick(false).f())

    val js: List<J> = G.entries
    for (x in js) println(x.g(3) + " " + x.h())
    println(G.P.h())

    val lambda: (I) -> Int = { it.f() }
    println(lambda(G.Q))
    println(call(lambda, F.Y))
    val ref: (I) -> Int = I::f
    println(ref(E.A))

    val any: Any = G.Q
    println((any as J).g(1))
    println(E.values().map { it as I }.sumOf { it.f() })
}
