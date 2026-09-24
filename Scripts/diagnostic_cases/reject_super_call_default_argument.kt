// EXPECT-REJECT
open class A { open fun f(x: Int = 1): String = "A$x" }
class B : A() {
    override fun f(x: Int): String = "B$x"
    fun g(): String = super.f()
}
