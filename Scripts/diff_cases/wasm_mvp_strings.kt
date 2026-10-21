// DIFF_JVM
// DIFF_WASM
// Wasm MVP shape: calls, branches, and loops whose output stays in string
// literals (non-string println sinks remain stubbed under KSWIFTK-WASM-0001).
fun describe(flag: Boolean): String = if (flag) "yes" else "no"

fun main() {
    println(describe(true))
    println(describe(false))
    var n = 0
    while (n < 3) {
        println(describe(n == 0))
        n += 1
    }
}
