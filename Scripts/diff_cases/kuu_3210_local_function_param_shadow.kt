// KUU-3210: a local function's own value parameters must shadow the
// function's name inside its body -- `a` in `fun a(a: Any) = a === 1.1`
// binds to the parameter (kotlinc), not the function (KSwiftK previously
// reported KSWIFTK-SEMA-0309). A function-typed same-named parameter also
// wins in call position: `fun f(f: () -> String) = f()` invokes the
// parameter.
// JetBrains: primitiveTypes/kt36952_identityEqualsWithBooleanInLocalFunction.kt
fun box(): String {
    fun a(a: Any) = a === 1.1 is Double
    return if (a(true)) "OK" else "Fail"
}

fun collideCall(): String {
    fun f(f: () -> String) = f()
    return f({ "OKf" })
}

fun countdown(n: Int): Int {
    fun cd(k: Int): Int = if (k <= 0) 0 else cd(k - 1)
    return cd(n)
}

fun main() {
    println(box())
    println(collideCall())
    println(if (countdown(3) == 0) "OKcd" else "Failcd")
}
