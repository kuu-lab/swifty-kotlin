enum class E {
    A { override fun join(vararg xs: String): String = xs.joinToString("-") },
    B { override fun join(vararg xs: String): String = "B" + xs.size };
    abstract fun join(vararg xs: String): String
}

enum class F {
    X { override fun sum(pre: String, vararg xs: Int): String = pre + xs.sum() };
    abstract fun sum(pre: String, vararg xs: Int): String
}

fun main() {
    println(E.A.join("a", "b"))
    println(E.A.join())
    println(E.B.join("x"))
    println(F.X.sum("s", 1, 2, 3))
}
