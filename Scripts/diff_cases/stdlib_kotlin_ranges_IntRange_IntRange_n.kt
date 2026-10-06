package diff

fun main() {
    val range = IntRange(2, 11)
    val same = 2..11
    val different = 2..12
    val empty = IntRange(10, 1)
    val otherEmpty = IntRange(7, 3)

    println("props=${range.start},${range.endInclusive},${range.endExclusive}")
    println("empty=${empty.isEmpty()},nonEmpty=${range.isEmpty()}")
    println("str=$range,$empty")
    println("eq=${range == same},neq=${range == different},crossEq=${range == empty}")
    println("emptyEq=${empty == otherEmpty}")
    println("hashEq=${range.hashCode() == same.hashCode()},emptyHash=${empty.hashCode()}")
    println("eqNull=${range.equals(null)},eqOther=${range.equals(5)}")

    val erased: Any = range
    println("boxed=${erased is IntRange},boxedEq=${erased == same}")
}
