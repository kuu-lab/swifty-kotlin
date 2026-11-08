// DIFF_JVM
// KUU-4134: distinctBy/zipWithNext erased-R placeholders must accept
// nullable selector results. Kotlin's K/R type parameters are unbounded
// (implicitly Any?), so a String? key or transform result is legal; the
// previous non-null Any placeholder rejected it with SEMA-0469.

data class User(val name: String, val nickname: String?)

fun main() {
    val users = listOf(
        User("Alice", "A"),
        User("Bob", null),
        User("Carol", "A"),
        User("Dave", null),
    )

    // Nullable keys deduplicate on first occurrence, including null.
    println(users.distinctBy { it.nickname })

    // Non-null key selector still works.
    println(users.distinctBy { it.name })

    // Sequence receiver path.
    println(users.asSequence().distinctBy { it.nickname }.toList())

    // zipWithNext's transform R is likewise unbounded.
    println(users.zipWithNext { a, b -> a.nickname })
    println(users.zipWithNext { a, b -> "${a.name}>${b.name}" })
}
