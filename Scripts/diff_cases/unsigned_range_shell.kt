fun main() {
    // KSP-709: unsigned range class shells are bundled Kotlin — exercise the
    // members that used to come from the synthetic stub.
    val uintRange = UIntRange(2u, 6u)
    println(uintRange.start)
    println(uintRange.endInclusive)
    println(uintRange.endExclusive)
    println(uintRange.first)
    println(uintRange.last)
    println(uintRange.step)
    println(uintRange.isEmpty())
    println(uintRange.contains(6u))
    println(6u in uintRange)
    println(uintRange.toString())
    println(uintRange == UIntRange(2u, 6u))
    println(uintRange.hashCode() == UIntRange(2u, 6u).hashCode())

    val ulongRange = ULongRange(3uL, 9uL)
    println(ulongRange.start)
    println(ulongRange.endInclusive)
    println(ulongRange.endExclusive)
    println(ulongRange.first)
    println(ulongRange.last)
    println(ulongRange.step)
    println(ulongRange.isEmpty())
    println(ulongRange.contains(9uL))
    println(5uL in ulongRange)
    println(ulongRange.toString())
    println(ulongRange == ULongRange(3uL, 9uL))
    println(ulongRange.hashCode() == ULongRange(3uL, 9uL).hashCode())

    // Companion EMPTY constants.
    println(UIntRange.EMPTY.isEmpty())
    println(UIntRange.EMPTY.first)
    println(UIntRange.EMPTY.last)
    println(ULongRange.EMPTY.isEmpty())
    println(ULongRange.EMPTY.first)
    println(ULongRange.EMPTY.last)

    // HOFs that used to be synthetic stub registrations.
    println(uintRange.take(2))
    println(uintRange.drop(2))
    println(ulongRange.take(3))
    println(ulongRange.drop(3))
    val it = ulongRange.iterator()
    println(it.hasNext())
    println(it.next())

    // for-in iteration over both source-backed classes.
    for (v in UIntRange(1u, 3u)) print("$v ")
    println()
    for (v in ULongRange(7uL, 9uL)) print("$v ")
    println()

    // Empty ranges: isEmpty + equality across differing bounds.
    val emptyUInt = UIntRange(5u, 1u)
    println(emptyUInt.isEmpty())
    println(emptyUInt == UIntRange.EMPTY)
    val emptyULong = ULongRange(9uL, 2uL)
    println(emptyULong.isEmpty())
    println(emptyULong == ULongRange.EMPTY)
}
