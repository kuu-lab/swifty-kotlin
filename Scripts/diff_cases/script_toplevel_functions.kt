// SKIP-DIFF (DEBT-DIFF-002): not a timeout — kswiftc only synthesizes an implicit `main` when
// a file has top-level statements AND no other top-level declarations (KotlinParser.parseFile
// scriptKind rule). Top-level `fun` here disqualifies script treatment, so the bare `println`
// calls below are silently dropped during AST building and linking fails with
// KSWIFTK-LINK-0002 (no `main`). kotlinc's real `.kts` script mode has no such restriction.
// The underlying logic (incl. recursion) is verified correct via the `main()`-wrapped twin:
// top_level_function_recursion.kt.
fun greet(name: String): String = "Hello, $name!"

fun add(a: Int, b: Int): Int = a + b

fun factorial(n: Int): Int = if (n <= 1) 1 else n * factorial(n - 1)

println(greet("World"))
println(add(3, 4))
println(factorial(5))
println(factorial(6))
