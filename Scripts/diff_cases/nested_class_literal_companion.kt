// KUU-1273: Qualified classifiers must not evaluate the outer companion.
package sample

class Outer {
    class Nested {
        init { println("constructed") }
        class Deep
    }
    companion object
}

class NamedOuter {
    class Nested
    companion object Factory
}

fun main() {
    println(Outer.Nested::class.qualifiedName)
    println(Outer.Nested::class.simpleName)
    println(Outer.Companion::class.qualifiedName)
    println(Outer.Nested.Deep::class.qualifiedName)
    println(Outer::class.qualifiedName)
    println(NamedOuter.Nested::class.qualifiedName)
    println(NamedOuter.Factory::class.qualifiedName)
    println(Outer.Nested()::class.qualifiedName)
    val Outer = NamedOuter.Nested()
    println(Outer::class.qualifiedName)
}
