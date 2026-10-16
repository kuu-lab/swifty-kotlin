open class A { open val foo: String = "A" }
open class B : A() { override val foo: String = "B" }
class C : B() {
    override val foo: String = "C"
    val directSuper: String = super<B>.foo
    inner class D {
        val result: String = super<B>@C.foo
        val outer: String = this@C.foo
    }
}

fun box(): String {
    val c = C()
    val d = c.D()
    return if (c.directSuper == "B" && d.result == "B" && d.outer == "C") "OK" else "FAIL"
}

fun main() { print(box()) }
