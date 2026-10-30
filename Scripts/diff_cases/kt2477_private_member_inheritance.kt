package test

interface A {
    public val c: String
        get() = "OK"
    fun foo(): String = "OK_FOO"
}

interface B {
    private val c: String
        get() = "FAIL_B"
    private fun foo(): String = "FAIL_B_FOO"
}

open class C {
    private val c: String = "FAIL_C"
    private fun foo(): String = "FAIL_C_FOO"
}

open class D: C(), A, B {
    val b = c
}

fun box(): String {
    val d = D()
    if (d.b != "OK") return "FAIL b: ${d.b}"
    if (d.c != "OK") return "FAIL c: ${d.c}"
    if (d.foo() != "OK_FOO") return "FAIL foo: ${d.foo()}"
    return "OK"
}

fun main() {
    println(box())
}
