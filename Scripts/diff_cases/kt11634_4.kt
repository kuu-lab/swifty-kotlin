interface A { fun foo(): String }

open class Base(val p: String) {
    open val a = object : A { override fun foo() = p }
}

open class Derived1(p: String) : Base(p) {
    override open val a = object : A { override fun foo() = "fail" }

    inner class Derived2(p: String) : Base(p) {
        val x = object : A by super<Base>@Derived1.a {}
    }
}

fun main() {
    val outer = Derived1("OK")
    println(outer.Derived2("inner").x.foo())
}
