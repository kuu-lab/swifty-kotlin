// Based on JetBrains/Kotlin 2.3.10 compiler/testData/codegen/box/casts/intersectionTypeMultipleBounds.kt.
interface A {
    fun foo(): Any?
    fun bar(): String
}

interface B {
    fun foo(): String
}

fun <T> bar(x: T): String where T : A, T : B {
    if (x.foo().length != 2 || x.foo() != "OK") return "fail 1"
    if (x.bar() != "ok") return "fail 2"
    return "OK"
}

fun <T> barReversed(x: T): String where T : B, T : A {
    if (x.foo().length != 2 || x.foo() != "OK") return "fail 1"
    if (x.bar() != "ok") return "fail 2"
    return "OK"
}

fun <T : B> singleBound(x: T): String = x.foo()

class C : A, B {
    override fun foo() = "OK"
    override fun bar() = "ok"
}

fun box(): String = bar(C())

fun main() {
    println(box())
    println(barReversed(C()))
    println(singleBound(C()))
}
