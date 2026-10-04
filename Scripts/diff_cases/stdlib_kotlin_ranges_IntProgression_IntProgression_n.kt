fun inspect(label: String, progression: IntProgression) {
    println("$label=${progression.first},${progression.last},${progression.step}")
    println(progression.toString())
    println(progression.hashCode())
    val iterator: IntIterator = progression.iterator()
    while (iterator.hasNext()) println(iterator.nextInt())
    println("exhausted=${iterator.hasNext()}")
    try {
        iterator.nextInt()
        println("unexpected element")
    } catch (e: NoSuchElementException) {
        println("NoSuchElementException")
    }
}

fun main() {
    val positive = IntProgression.fromClosedRange(2, 12, 3)
    val same = IntProgression.fromClosedRange(2, 11, 3)
    val negative = 10 downTo 1 step 3
    val emptyPositive = IntProgression.fromClosedRange(10, 1, 3)
    val emptyNegative = IntProgression.fromClosedRange(1, 10, -2)
    inspect("positive", positive)
    inspect("negative", negative)
    inspect("emptyPositive", emptyPositive)
    inspect("emptyNegative", emptyNegative)
    inspect("singleton", IntProgression.fromClosedRange(7, 7, -4))
    inspect("max", IntProgression.fromClosedRange(Int.MAX_VALUE - 2, Int.MAX_VALUE, 2))
    inspect("min", IntProgression.fromClosedRange(Int.MIN_VALUE + 2, Int.MIN_VALUE, -2))
    inspect("wide", IntProgression.fromClosedRange(Int.MIN_VALUE, Int.MAX_VALUE, Int.MAX_VALUE))
    println("equal=${positive == same},${positive.equals(same)}")
    println("sameHash=${positive.hashCode() == same.hashCode()}")
    println("different=${positive.equals(negative)},${positive.equals(IntProgression.fromClosedRange(2, 11, 1))}")
    println("emptyEqual=${emptyPositive == emptyNegative},${emptyPositive.equals(emptyNegative)}")
    println("emptyNonempty=${emptyPositive.equals(positive)},${positive.equals(emptyPositive)}")
    println("unrelated=${positive.equals(null)},${positive.equals(1)},${positive.equals("2..11 step 3")}")
    val erased: Any = positive
    println("erased=${erased.equals(same)},${erased.hashCode()},${erased.toString()}")
    val iterable: Iterable<Int> = positive
    for (value in iterable) println("iterable=$value")
    val genericIterator: Iterator<Int> = positive.iterator()
    println("next=${genericIterator.next()}")
    for (value in 1..3) println("range=$value")
    println("range=${(1..3).toString()},${(1..3).hashCode()},${(1..3).equals(1..3)}")
    try {
        IntProgression.fromClosedRange(1, 3, 0)
        println("accepted zero step")
    } catch (e: IllegalArgumentException) {
        println("zero=${e.message}")
    }
    try {
        IntProgression.fromClosedRange(1, 3, Int.MIN_VALUE)
        println("accepted minimum step")
    } catch (e: IllegalArgumentException) {
        println("minimum=${e.message}")
    }
}
