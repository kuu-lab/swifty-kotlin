// KUU-4089: a `;` inside a trailing lambda used as a when-branch body must
// stay inside the lambda. A top-level-looking `;` once ended the entry early,
// so `g { h(1); h(2) }` misparsed the `}` and the remaining entries failed.
var log = ""

fun g(b: () -> Unit) { b() }
fun h(x: Int) { log += "h$x;" }

// Subjectless when as a function body expression (declaration tail).
fun select(mode: Int) = when {
    mode == 0 -> g { h(1); h(2) }
    else -> {}
}

// Subject when as a function body expression; else branch also a lambda call.
fun pick(x: Int) = when (x) {
    1 -> g { h(3); h(4) }
    else -> g { h(5); h(6) }
}

// Statement-position when inside a block.
fun runStatementForm(flag: Boolean) {
    when {
        flag -> g { h(7); h(8) }
        else -> g { h(9); h(10) }
    }
}

fun main() {
    select(0)
    select(1)
    pick(1)
    pick(9)
    runStatementForm(true)
    runStatementForm(false)
    println(log)
}
