// KUU-3628: `enum class E : C by <expr>` used to compile but panic at
// runtime (KSWIFTK-LINK-0003). The delegation field was enumerated as a
// phantom enum entry and the synthesized forwarding members read the
// delegate through an object-field offset, which an ordinal-backed enum
// value does not have.

interface C {
    fun f(): String
    val tag: String
}

object Impl : C {
    override fun f() = "OK"
    override val tag: String = "impl-tag"
}

enum class E : C by Impl { A, B }

enum class F(c: C) : C by c { X(Impl), Y(Impl) }

fun main() {
    println(E.A.f())
    println(E.B.tag)
    val c: C = E.A
    println(c.f())
    println(c.tag)
    println(E.entries.size)
    println(E.values().size)
    println(E.A.ordinal)
    println(E.B.name)
    println(F.X.f())
    println(F.Y.tag)
}
