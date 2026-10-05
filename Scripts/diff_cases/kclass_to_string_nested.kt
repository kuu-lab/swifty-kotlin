// KUU-1262: JVM binary names retain package dots and use $ between class owners.
package Sample.deep

import Sample.deep.Outer.Nested.Deep

class Outer {
    class Nested { class Deep }
    inner class Inner
    object Named
}
class WithCompanion { companion object }
class lower { class nested }

fun main() {
    println(Outer::class)
    println(Outer.Nested::class)
    println(Outer.Nested::class.toString())
    println(Deep::class)
    println(Outer.Inner::class)
    println(Outer.Named::class)
    println(WithCompanion.Companion::class)
    println(lower.nested::class)
    println(Outer.Nested::class.qualifiedName)
    println(Outer.Nested::class.simpleName)
    val erased: Any = Outer.Nested()
    println(erased::class)
    println(erased::class.toString())
    println("class=${Outer.Nested::class}")
    println(listOf(Outer.Nested::class))
}
