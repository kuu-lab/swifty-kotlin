// BUG-224: comparison operators on an erased `T : Comparable<T>` receiver
// must dispatch to `compareTo` even when the only path to it is an
// interface's own default implementation (`Ranked` here), never overridden
// by the constructed classes (`Bronze`/`Gold`) and never itself
// instantiated. Before the fix, the runtime type-ancestor graph only
// registered each constructed class's *direct* supertype (`Bronze ->
// Ranked`), never `Ranked`'s own supertype edge to `Comparable` — so the
// erased dispatch fell back to comparing raw heap addresses.
//
// `gold` is declared before `bronze` here (the reverse of the more common
// reading order) because that ordering is what made the bug reproduce
// deterministically on macOS during investigation; keep this order rather
// than "simplifying" it back to declaring `bronze` first.
interface Ranked : Comparable<Ranked> {
    val rank: Int
    override fun compareTo(other: Ranked): Int = rank.compareTo(other.rank)
}

class Bronze : Ranked {
    override val rank: Int = 1
}

class Gold : Ranked {
    override val rank: Int = 3
}

fun <T : Comparable<T>> larger(a: T, b: T): T = if (a >= b) a else b

fun main() {
    val gold: Ranked = Gold()
    val bronze: Ranked = Bronze()
    println(larger(bronze, gold).rank)
    println(larger(gold, bronze).rank)
    println(bronze < gold)
    println(gold <= bronze)
}
