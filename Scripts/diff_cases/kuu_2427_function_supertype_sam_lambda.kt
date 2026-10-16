// KUU-2427: A synthetic FunctionN.invoke is the inherited SAM method.
fun interface Foo : () -> Int

fun box(): String {
    val foo = Foo { 42 }
    return if (foo.invoke() == 42) "OK" else "FAIL"
}

fun main() {
    println(box())
}
