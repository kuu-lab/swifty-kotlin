// KUU-2092: preserve the invariant and contravariant reproducer from Kotlin's
// compiler/testData/codegen/box/bridges/test23.kt (Kotlin 2.3.10).
open class Foo(val x: Int)

abstract class Base<T> {
    abstract fun bar(x: T)
}

class Derived<T : Foo> : Base<T>() {
    override fun bar(x: T) { }
}

abstract class Base2<in T> {
    abstract fun bar(x: T)
}

class Derived2<in T : Foo> : Base2<T>() {
    override fun bar(x: T) { }
}

fun box(): String {
    val d = Derived<Foo>()
    try {
        val x = (d as Base<Any>).bar(Any())
        return "FAIL 1: $x"
    } catch (e: ClassCastException) {}
    val d2 = Derived2<Foo>()
    try {
        val x = (d2 as Base2<Any>).bar(Any())
        return "FAIL 2: $x"
    } catch (e: ClassCastException) {}
    return "OK"
}

fun main() {
    println(box())
}
