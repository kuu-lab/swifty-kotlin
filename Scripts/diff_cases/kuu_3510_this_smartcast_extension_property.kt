// KUU-3510: A smart-cast of `this` must make an inferred extension property applicable.
open class KFoo {
    fun foo(): String {
        if (this is KFooQux) return qux
        throw AssertionError()
    }
}

class KFooQux : KFoo()

val KFooQux.qux get() = "OK"

fun main() {
    println(KFooQux().foo())
}
