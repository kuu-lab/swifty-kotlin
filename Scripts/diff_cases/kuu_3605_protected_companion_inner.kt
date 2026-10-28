// KUU-3605: a protected member of a companion object is scoped to the
// companion's containing class — code lexically inside the class sees it,
// including inner and nested classes (JetBrains codegen/box/regressions/
// kt5395.kt).
class D {
    companion object {
        protected val F: String = "OK"
        protected fun g(): String = "GEN"
    }
    inner class E {
        fun foo() = F
        fun bar() = g()
        fun qualified() = D.F
        fun viaCompanion() = Companion.F
    }
    class N {
        fun foo() = F
    }
    inner class E2 {
        inner class Deep {
            fun foo() = F
        }
    }
    object O {
        fun foo() = F
    }
    fun self() = F
}
fun main() {
    println(D().E().foo())
    println(D().E().bar())
    println(D().E().qualified())
    println(D().E().viaCompanion())
    println(D.N().foo())
    println(D().E2().Deep().foo())
    println(D.O.foo())
    println(D().self())
}
