interface A {
    private fun foo() = "OK"
    public fun bar() = foo()
}

class B : A {
    private fun foo() = "fail"
}

interface MinimalA {
    private fun foo() = "OK"
    public fun bar() = foo()
}

class MinimalB : MinimalA {
    private fun foo() = "other"
}

fun box() = B().bar()
fun minimalBox() = MinimalB().bar()

fun main() {
    println(if (box() == "OK" && minimalBox() == "OK") "OK" else "FAIL")
}
