// SKIP-DIFF (DEBT-DIFF-002): not a timeout — kswiftc only synthesizes an implicit `main` when
// a file has top-level statements AND no other top-level declarations (KotlinParser.parseFile
// scriptKind rule). The top-level `fun`/`data class` here disqualify script treatment, so the
// bare `println` calls below are silently dropped during AST building and linking fails with
// KSWIFTK-LINK-0002 (no `main`). kotlinc's real `.kts` script mode has no such restriction.
// The underlying logic is verified correct via the `main()`-wrapped twin:
// top_level_extension_data_class.kt.
// カスタム拡張関数
fun String.isPalindrome(): Boolean {
    return this == this.reversed()
}

// データクラス
data class Person(val name: String, val age: Int)

fun Person.isAdult(): Boolean = age >= 18

val text = "level"
val person = Person("Alice", 25)

println("'$text' is palindrome: ${text.isPalindrome()}")
println("${person.name} is adult: ${person.isAdult()}")
