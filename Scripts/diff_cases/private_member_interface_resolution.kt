// KUU-3585: inherited private members must not shadow an accessible interface property.
interface A { public val c: String get() = "OK" }
interface B { private val c: String get() = "FAIL" }
open class C { private val c: String = "FAIL" }
open class D : C(), A, B { val b = c }

fun main() {
    println(D().c)
}
