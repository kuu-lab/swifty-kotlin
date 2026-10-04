open class P {
    class Q : P()
    object O : P()
}

class Wrapper {
    class Item(val v: Int) {
        fun twice() = v * 2
    }
}

sealed class S {
    data class A(val n: Int) : S()
    object B : S()
}

fun main() {
    val q = P.Q()
    println(q is P.Q)
    println(q is P)

    val p: P = q
    println(p == P.O)

    val erased: Any = P.Q()
    println(erased is P.Q)

    val s: S = S.A(5)
    println(s is S.A)
    println(when (s) {
        is S.A -> "A${s.n}"
        S.B -> "B"
    })

    println(Wrapper.Item(5).twice())
    println(S.A(5))
}
