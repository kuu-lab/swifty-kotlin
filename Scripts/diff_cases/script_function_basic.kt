// SKIP-DIFF (DEBT-DIFF-002): script-style diff runner parity / timeout tracking
fun greet(name: String): String {
    return "Hello, $name!"
}

fun add(a: Int, b: Int): Int = a + b

println(greet("World"))
println(add(5, 3))
