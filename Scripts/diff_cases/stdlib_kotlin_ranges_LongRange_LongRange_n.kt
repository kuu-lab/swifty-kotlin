package diff

fun main() {
    val range = LongRange(2L, 11L)
    val same = 2L..11L
    val different = 2L..12L
    val empty = LongRange(10L, 1L)
    val otherEmpty = LongRange(7L, 3L)

    println("props=${range.start},${range.endInclusive},${range.endExclusive}")
    println("empty=${empty.isEmpty()},nonEmpty=${range.isEmpty()}")
    println("str=$range,$empty")
    println("eq=${range == same},neq=${range == different},crossEq=${range == empty}")
    println("emptyEq=${empty == otherEmpty}")
    println("hashEq=${range.hashCode() == same.hashCode()},emptyHash=${empty.hashCode()}")
    println("eqNull=${range.equals(null)},eqOther=${range.equals(5L)}")
}
