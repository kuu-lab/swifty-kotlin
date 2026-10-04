// BUG-165: two or more top-level properties initialized with a branching
// expression used to crash codegen (duplicate KIR labels injected into main).
val a = if (1 > 2) 1 else 2
val b = if (1 < 2) 3 else 4
val c = if (a < b) { a + b } else { a - b }
val d = when {
    a > b -> 100
    a < b -> 200
    else -> 300
}
var e = if (d == 200) a * b else 0
val f = if (a < b) true else false
val g = if (a < b) "lt" else "ge"
val h = if (g == "lt") g.length else 0

fun main() {
    println(a)
    println(b)
    println(c)
    println(d)
    println(e)
    println(f)
    println(g)
    println(h)
    println(g.length)
    println(g)
    if (a < b) {
        println("a<b")
    } else {
        println("a>=b")
    }
    for (i in 0 until 3) {
        e = e + i
    }
    println(e)
}
