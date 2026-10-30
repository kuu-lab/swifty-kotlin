// KUU-3201: anonymous functions carrying enclosing-loop jumps inside inline
// calls — the machinery behind `jump to undefined label -1000x` when such a
// body was materialised into a `kk_function_value_adapter_*`. kotlinc-accepted.
inline fun foo(block: () -> Unit) = block()
inline fun useBoth(a: () -> Unit, b: () -> Unit) { a(); b() }

fun main() {
    var i = 0
    outer@ while (i < 5) {
        i++
        foo(fun() { if (i == 2) continue@outer })
        useBoth(fun() { if (i == 4) continue@outer }, fun() {})
    }
    println("done i=$i")
}
