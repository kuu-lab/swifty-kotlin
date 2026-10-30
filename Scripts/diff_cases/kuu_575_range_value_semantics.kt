fun main() {
    val intRange = 1..3
    val sameIntRange = 1..3
    val differentIntRange = 1..4
    val emptyIntRange = 5..2
    val otherEmptyIntRange = 10..0
    val steppedProgression = 1..10 step 3
    val sameSteppedProgression = 1..10 step 3
    val steppedLongProgression = 1L..10L step 3
    val sameSteppedLongProgression = 1L..10L step 3
    val steppedCharProgression = 'a'..'f' step 2
    val sameSteppedCharProgression = 'a'..'f' step 2
    val longUntil = 4294967297L until 4294967300L
    val sameLongUntil = 4294967297L until 4294967300L
    val longDownTo = 4294967299L downTo 4294967297L
    val sameLongDownTo = 4294967299L downTo 4294967297L
    val charUntil = 'a' until 'c'
    val sameCharUntil = 'a' until 'c'
    val charDownTo = 'c' downTo 'a'
    val sameCharDownTo = 'c' downTo 'a'
    val longRange = 1L..3L
    val charRange = 'a'..'c'

    println(intRange == sameIntRange)
    println(intRange == differentIntRange)
    println(emptyIntRange == otherEmptyIntRange)
    println(steppedProgression == sameSteppedProgression)
    println(steppedLongProgression == sameSteppedLongProgression)
    println(steppedCharProgression == sameSteppedCharProgression)
    println(longUntil == sameLongUntil)
    println(longDownTo == sameLongDownTo)
    println(charUntil == sameCharUntil)
    println(charDownTo == sameCharDownTo)
    println(longRange == (1L..3L))
    println(charRange == ('a'..'c'))

    println(intRange.hashCode())
    println(emptyIntRange.hashCode())
    println(steppedProgression.hashCode())
    println(steppedLongProgression.hashCode())
    println(steppedCharProgression.hashCode())
    println(longUntil.hashCode())
    println(longDownTo.hashCode())
    println(charUntil.hashCode())
    println(charDownTo.hashCode())
    println(longRange.hashCode())
    println(charRange.hashCode())

    println(listOf(intRange).contains(sameIntRange))
    println(mapOf(intRange to "int")[sameIntRange])
    println(intRange.equals(sameIntRange))
    println(intRange.hashCode() == sameIntRange.hashCode())
}
