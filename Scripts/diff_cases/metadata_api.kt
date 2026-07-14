// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
// STDLIB-REFL-172: metadata API baseline

annotation class Meta(val label: String)

@Meta("demo")
data class User(val name: String, val age: Int)

fun main() {
    val klass = User::class
    println(klass.qualifiedName ?: "<unknown>")
    println(klass.isData)
    println(klass.constructors.size)
    println(klass.annotations.size)
    val annotation = klass.findAnnotation<Meta>()
    println(annotation != null)
}
