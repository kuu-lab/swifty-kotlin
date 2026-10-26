// KUU-3549: enum-entry overrides may qualify super with the enclosing enum.
enum class E {
    E1 { override fun f() = super<E>.f() + "O" },
    E2 { override fun f() = super<E>.f() + "K" };
    open fun f() = ""
}

fun main() { println(E.E1.f() + E.E2.f()) }
