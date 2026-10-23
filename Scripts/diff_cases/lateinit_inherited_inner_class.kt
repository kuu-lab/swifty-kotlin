// KUU-2913: `this::bar.isInitialized` in an inner subclass must inspect the inherited field on the inner instance.
open class Foo {
    lateinit var bar: String
    inner class InnerSubclass : Foo() {
        fun testInner(): String = if (this::bar.isInitialized) "Fail" else "OK"
    }
}
fun main() { println(Foo().InnerSubclass().testInner()) }
