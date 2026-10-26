// Regression from JetBrains testData/codegen/box/functions/invoke/kt3772.kt:
// prefer D.attr over the applicable but less-specific C.attr extension.
open class A { fun invoke(f: A.() -> Unit) = 1 }
class B { operator fun invoke(f: B.() -> Unit) = 2 }
open class C
val C.attr: A get() = A()
open class D : C()
val D.attr: B get() = B()

fun main() {
    val d = D()
    println(d.attr {})
}
