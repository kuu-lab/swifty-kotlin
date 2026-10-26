inline fun foo(block: () -> Unit) = block()

fun main() {
    var i = 0
    outer@ while (true) {
        i += 1
        foo(fun() { if (i == 2) break@outer })
        if (i > 5) break
    }
    println("i=$i")
}
