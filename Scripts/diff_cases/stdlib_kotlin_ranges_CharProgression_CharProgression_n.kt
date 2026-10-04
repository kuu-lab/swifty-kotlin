fun describe(p: CharProgression) {
    println("properties=${p.first.code},${p.last.code},${p.step}")
    println("text=${p.toString()},hash=${p.hashCode()}")
    val iterator: CharIterator = p.iterator()
    while (iterator.hasNext()) {
        println("char=${iterator.nextChar().code}")
    }
    println("exhausted=${iterator.hasNext()}")
    try {
        iterator.nextChar()
    } catch (e: NoSuchElementException) {
        println("nextChar exhausted")
    }
    try {
        iterator.next()
    } catch (e: NoSuchElementException) {
        println("next exhausted")
    }
}

fun main() {
    val ascending = CharProgression.fromClosedRange('a', 'h', 3)
    val same = CharProgression.fromClosedRange('a', 'g', 3)
    val descending = CharProgression.fromClosedRange('h', 'a', -3)
    val emptyUp = CharProgression.fromClosedRange('z', 'a', 2)
    val emptyDown = CharProgression.fromClosedRange('a', 'z', -3)
    describe(ascending)
    describe(descending)
    describe(emptyUp)
    describe(emptyDown)
    describe(CharProgression.fromClosedRange('x', 'x', Int.MAX_VALUE))
    println("equal=${ascending.equals(same)},${ascending == same}")
    println("differentStep=${ascending.equals(CharProgression.fromClosedRange('a', 'g', 2))}")
    println("differentFirst=${ascending.equals(CharProgression.fromClosedRange('b', 'h', 3))}")
    println("differentLast=${ascending.equals(CharProgression.fromClosedRange('a', 'j', 3))}")
    println("empty=${emptyUp.equals(emptyDown)},${emptyUp.hashCode()},${emptyDown.hashCode()}")
    println("unrelated=${ascending.equals(null)},${ascending.equals(1)},${ascending.equals("a..g")},${ascending.equals(1..3)}")

    val unitStep = CharProgression.fromClosedRange('a', 'c', 1)
    val range = 'a'..'c'
    println("range=${unitStep.equals(range)},${range.equals(unitStep)}")
    println("emptyRange=${emptyUp.equals('z'..'a')},${('z'..'a').equals(emptyUp)}")
    val rangeIterator: CharIterator = range.iterator()
    println("rangeIterator=${rangeIterator.nextChar()},${rangeIterator.next()},${rangeIterator.nextChar()},${rangeIterator.hasNext()}")
    val iterable: Iterable<Char> = ascending
    println("iterable=${iterable.joinToString()}")
    val any: Any = ascending
    println("any=${any.equals(same)},${any.hashCode()},${any.toString()}")
    println("anyDifferent=${any.equals(descending)},${any.equals(null)},${any.equals(1)}")
    val anyRange: Any = range
    println("anyRange=${anyRange.equals(unitStep)},${anyRange.toString()}")
    println("anyProgressionRange=${(unitStep as Any).equals(range)},${(unitStep as Any).equals(anyRange)}")
    println("anyDescending=${(descending as Any).toString()}")
    val nullableAny: Any? = anyRange
    val nullAny: Any? = null
    println("safeAny=${nullableAny?.equals(unitStep)},${nullAny?.equals(unitStep)}")
    val upcastRange: CharProgression = range
    println("upcastRange=${upcastRange.equals(unitStep)},${upcastRange.hashCode()},${upcastRange.toString()}")
    println("interpolated=$ascending")

    val upper = CharProgression.fromClosedRange('\uFFFD', Char.MAX_VALUE, 1).iterator()
    while (upper.hasNext()) println("upper=${upper.nextChar().code}")
    val lower = CharProgression.fromClosedRange('\u0002', Char.MIN_VALUE, -1).iterator()
    while (lower.hasNext()) println("lower=${lower.nextChar().code}")
    val wide = CharProgression.fromClosedRange(Char.MIN_VALUE, Char.MAX_VALUE, 32768).iterator()
    while (wide.hasNext()) println("wide=${wide.nextChar().code}")
    val huge = CharProgression.fromClosedRange(Char.MAX_VALUE, Char.MIN_VALUE, -Int.MAX_VALUE).iterator()
    while (huge.hasNext()) println("huge=${huge.nextChar().code}")
}
