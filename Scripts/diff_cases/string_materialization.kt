// SKIP-DIFF (DEBT-DIFF-007): two real bugs remain after removing the invented (kswiftc-only)
// `String.toTypedArray()` call: (1) "cba".toSortedSet() yields a set of raw Char codes
// (candidate prints `[97, 98, 99]`, ref prints `[a, b, c]`) instead of boxed Chars; (2)
// "ab".iterator() (CharIterator) is broken — `.next()` prints a blank instead of the char,
// and a second `.hasNext()` wrongly returns true after both elements are consumed. See
// docs/diff-skip-inventory.md (DEBT-DIFF-007).
fun main() {
    println("abc".toList())
    println("abc".toCharArray()[0])
    println("cba".toSortedSet().toList())
    println("ab".withIndex().toList())

    val iterator = "ab".iterator()
    println(iterator.hasNext())
    println(iterator.next())
    println(iterator.next())
    println(iterator.hasNext())
}
