open class A {
    companion object { protected fun foo() = "OK" }
    class B : A() {
        fun bar() = foo()
    }
}

fun main() { println(A.B().bar()) }
