// KUU-3586: delegated interface methods resolve inside the delegating class body.

interface Trait { fun foo() = "O"; fun bar(): String }
class SimpleClass : Trait { override fun bar() = "K" }

class ComplexClass : Trait by SimpleClass() {
    fun qux() = foo() + bar()
}

fun main() {
    println(ComplexClass().qux())
}
