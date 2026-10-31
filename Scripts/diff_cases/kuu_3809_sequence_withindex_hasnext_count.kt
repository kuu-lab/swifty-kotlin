// KUU-3809: Sequence.withIndex()/mapIndexed() iterators must not call the
// source iterator's hasNext() from inside next(). The extra call (one per
// element) made a for loop invoke source hasNext() 2n+1 times instead of n+1,
// observable through counting iterators (upstream discovery:
// codegen/box/controlStructures/forInSequenceWithIndex/forInSequenceWithIndexCheckSideEffects.kt).
// KOTLINC_FLAGS: -XXLanguage:+NameBasedDestructuring -XXLanguage:+DeprecateNameMismatchInShortDestructuringWithParentheses -XXLanguage:+EnableNameBasedDestructuringShortForm

class CS<out T>(private val s: Sequence<T>) : Sequence<T> {
    var c = 0
    inner class I(private val it: Iterator<T>) : Iterator<T> {
        override fun hasNext() = it.hasNext().also { c++ }
        override fun next() = it.next()
    }
    override fun iterator() = I(s.iterator())
}

fun main() {
    val xs = CS(listOf("a","b").asSequence())
    for ([i, x] in xs.withIndex()) { }
    println("withIndex=${xs.c}")

    val ys = CS(listOf("a","b","c").asSequence())
    for ((index, value) in ys.withIndex()) { }
    println("parenWithIndex=${ys.c}")

    val zs = CS(listOf("a","b","c","d").asSequence())
    for (e in zs.mapIndexed { index, value -> value }) { }
    println("mapIndexed=${zs.c}")
}
