class IntSequence : Sequence<Int> {
    override fun iterator(): Iterator<Int> = listOf(1).iterator()
}

fun <S : Sequence<Int>> appendTypeParam(s: S): Int =
    sequenceOf(1).flatMapTo(mutableListOf<Int>()) { s }.size

fun appendConcrete(): Int =
    sequenceOf(1).flatMapTo(mutableListOf<Int>()) { IntSequence() }.size

fun main() {
    println(appendTypeParam(sequenceOf(2)))
    println(appendConcrete())
}
