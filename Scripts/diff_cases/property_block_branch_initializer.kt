// BUG-047: top-level / class member property initializers that end in an
// expression with several top-level `{ }` blocks (`if/else`, `else if` chains)
// used to lose everything after the first block during CST splitting, so the
// false path of an `if/else` initializer evaluated to garbage.
val topLevelIf = if (1 > 2) { "yes" } else { "no" }

class Holder {
    val member = if (1 > 2) { "member-yes" } else { "member-no" }
    val memberChained = if (1 < 2) { "first" } else if (2 > 3) { "second" } else { "third" }
    val memberWhen = when (3) {
        1 -> { "one" }
        else -> { "other" }
    }
    val memberTry = try { "try" } catch (e: Exception) { "catch" } finally { }
}

fun main() {
    println(topLevelIf)
    val h = Holder()
    println(h.member)
    println(h.memberChained)
    println(h.memberWhen)
    println(h.memberTry)
}
