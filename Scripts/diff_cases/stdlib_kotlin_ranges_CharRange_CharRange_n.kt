package diff

fun main() {
    val range = CharRange('b', 'j')
    val same = 'b'..'j'
    val different = 'b'..'k'
    val empty = CharRange('z', 'a')
    val otherEmpty = CharRange('y', 'b')

    println("props=${range.start},${range.endInclusive},${range.endExclusive}")
    println("empty=${empty.isEmpty()},nonEmpty=${range.isEmpty()}")
    println("str=$range,$empty")
    println("eq=${range == same},neq=${range == different},crossEq=${range == empty}")
    println("emptyEq=${empty == otherEmpty}")
    println("hashEq=${range.hashCode() == same.hashCode()},emptyHash=${empty.hashCode()}")
    println("eqNull=${range.equals(null)},eqOther=${range.equals(5)}")
}
