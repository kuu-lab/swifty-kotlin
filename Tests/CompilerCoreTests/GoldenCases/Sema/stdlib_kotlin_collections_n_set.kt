// KUU-1597 Sema owner: pin setOf/setOfNotNull generic inference, nullability, and spread overloads; collection contents stay in Scripts/diff_cases/stdlib_kotlin_collections_n_set.kt.
fun main() {
    val singleton: Set<Int> = setOf(1)
    val nullableSingleton: Set<String?> = setOf(null as String?)
    val nonNullSingleton: Set<String> = setOfNotNull("a")
    val empty: Set<String> = setOfNotNull<String>()
    val allNull: Set<String> = setOfNotNull<String>(null, null)
    val mixed: Set<String> = setOfNotNull("a", null, "b", "a")
    val source: Array<String?> = arrayOf("x", null, "y", "x")
    val spread: Set<String> = setOfNotNull(*source)
}
