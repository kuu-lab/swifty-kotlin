// EXPECT-REJECT
// KUU-3141: Kotlin/JVM rejects accessing a companion's non-@JvmStatic
// protected member from a subclass that is not lexically nested inside the
// containing class ("protected members that are not '@JvmStatic' in the
// superclass companion is not yet supported").
open class A {
    companion object {
        protected fun foo() = "OK"
    }
}
class B : A() {
    fun bar() = foo()
}
fun main() { println(B().bar()) }
