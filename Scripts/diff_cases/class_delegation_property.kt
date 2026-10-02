// CLASS-008: class delegation must forward interface `val`/`var` properties
// through the delegate, not just functions.
interface I {
    fun a(): String
    fun b(): String
    val p: Int
    val s: String
    var m: Int
}

class Impl : I {
    override fun a() = "implA"
    override fun b() = "b->" + a()
    override val p = 1
    override val s = "hello"
    override var m = 5
}

class Wrapper(d: I) : I by d {
    override fun a() = "wrapA"
}

class Wrapper2(private val d: I) : I by d {
    override val p get() = d.p + 100
    fun both() = a() + b()
}

fun main() {
    println(Wrapper(Impl()).b())
    println(Wrapper(Impl()).a())
    println(Wrapper(Impl()).p)
    println(Wrapper(Impl()).s)

    val w = Wrapper(Impl())
    w.m = 42
    println(w.m)

    val w2 = Wrapper2(Impl())
    println(w2.p)
    println(w2.both())

    val asI: I = Wrapper(Impl())
    println(asI.p)
    println(asI.p + 1)
}
