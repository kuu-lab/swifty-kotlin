// SKIP-DIFF (DEBT-DIFF-002): not a timeout — kswiftc only synthesizes an implicit `main` when
// a file has top-level statements AND no other top-level declarations (KotlinParser.parseFile
// scriptKind rule). Top-level `fun` here disqualifies script treatment, so the bare `println`
// calls below are silently dropped during AST building and linking fails with
// KSWIFTK-LINK-0002 (no `main`). kotlinc's real `.kts` script mode has no such restriction.
// The underlying logic is verified correct via the `main()`-wrapped twin: top_level_function_basic.kt.
fun greet(name: String): String {
    return "Hello, $name!"
}

fun add(a: Int, b: Int): Int = a + b

println(greet("World"))
println(add(5, 3))
