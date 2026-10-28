// KUU-3672: an inner class declared in an enum entry body must delegate to
// the actual enum entry instance, not a null placeholder.
interface IFoo { fun foo(): String }
interface IBar { fun bar(): String }

enum class Test : IFoo, IBar {
    FOO {
        inner class Inner : IFoo by FOO
        val z = Inner()
        override fun foo() = "OK"
        override fun bar() = z.foo()
    }
}

fun box() = Test.FOO.bar()
fun main() { println(box()) }
