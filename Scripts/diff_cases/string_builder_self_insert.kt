// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: string_builder_self_insert.expected.stdout
// KUU-4518: StringBuilder.insert(Int, CharSequence) self-overlap differs across
// JDK releases, so pin KSwiftK's shifted-read result instead of comparing it
// against a local kotlinc/JDK reference.
fun main() {
    val self = StringBuilder(2).append("ab")
    self.insert(1, self)
    println(self.capacity())
    println(self.toString())

    val aliased = StringBuilder("ab")
    aliased.insert(1, aliased)
    println(aliased.toString())

    val aliasedAtZero = StringBuilder("ab")
    aliasedAtZero.insert(0, aliasedAtZero)
    println(aliasedAtZero.toString())

    val aliasedAtEnd = StringBuilder("ab")
    aliasedAtEnd.insert(2, aliasedAtEnd)
    println(aliasedAtEnd.toString())

    val aliasedLongAtZero = StringBuilder("abc")
    aliasedLongAtZero.insert(0, aliasedLongAtZero)
    println(aliasedLongAtZero.toString())

    val aliasedLongAtOne = StringBuilder("abc")
    aliasedLongAtOne.insert(1, aliasedLongAtOne)
    println(aliasedLongAtOne.toString())

    val aliasedLongAtEnd = StringBuilder("abc")
    aliasedLongAtEnd.insert(3, aliasedLongAtEnd)
    println(aliasedLongAtEnd.toString())
}
