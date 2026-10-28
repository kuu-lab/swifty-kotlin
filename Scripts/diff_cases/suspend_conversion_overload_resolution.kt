var foo1 = false
var foo2 = false

fun foo(x: () -> Int) { foo1 = true }
fun foo(x: suspend () -> Int) { foo2 = true }

fun test(f: () -> Int, g: suspend () -> Int) {
    foo(f)
    foo(g)
}

fun box(): String {
    test({ 1 }, { 2 })
    return if (foo1 && foo2) "OK" else "foo1: $foo1; foo2: $foo2"
}

fun main() {
    println(box())
}
