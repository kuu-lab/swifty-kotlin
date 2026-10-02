package diff

fun openEndRangeMembers(range: OpenEndRange<Int>): Boolean =
    range.start < range.endExclusive && range.contains(3) && !range.isEmpty()

fun main() {
    val open: OpenEndRange<Int> = 1..<5
    println(open.start)
    println(open.endExclusive)
    println(open.contains(3))
    println(open.contains(5))
    println(open.isEmpty())
    println(3 in open)
    println(5 in open)

    val empty: OpenEndRange<Int> = 5..<5
    println(empty.isEmpty())
    println(empty.contains(5))

    val chars: OpenEndRange<Char> = 'a'..<'e'
    println(chars.start)
    println(chars.endExclusive)
    println(chars.contains('c'))
    println(chars.isEmpty())

    val longs: OpenEndRange<Long> = 1L..<10L
    println(longs.start)
    println(longs.endExclusive)
    println(longs.contains(7L))
    println(longs.isEmpty())

    println(openEndRangeMembers(open))
    println(openEndRangeMembers(empty))
}
