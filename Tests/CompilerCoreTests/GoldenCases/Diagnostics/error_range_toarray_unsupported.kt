// Real kotlinc has no toIntArray()/toLongArray()/toUIntArray()/toULongArray()
// directly on IntRange/LongRange/UIntRange/ULongRange or their Progressions --
// only Collection<T>.toXxxArray() exists, and a range is Iterable, not
// Collection. KSwiftK used to expose these as synthetic/source-backed range
// members anyway (a KSwiftK-only superset never re-examined across the
// KSP-453/1529/1530 "Kotlinize" migrations). Correct usage goes through
// toList() first -- see Scripts/diff_cases/range_basic.kt.

fun main() {
    // ERROR: no direct toIntArray() on IntRange
    val a = (1..7).toIntArray()  // KSWIFTK-SEMA-0024: unresolved member function 'toIntArray'

    // ERROR: no direct toIntArray() on IntProgression
    val b = (1..7 step 2).toIntArray()  // KSWIFTK-SEMA-0024: unresolved member function 'toIntArray'

    // ERROR: no direct toLongArray() on LongRange
    val c = (1L..7L).toLongArray()  // KSWIFTK-SEMA-0024: unresolved member function 'toLongArray'

    // ERROR: no direct toLongArray() on LongProgression
    val d = (1L..7L step 2).toLongArray()  // KSWIFTK-SEMA-0024: unresolved member function 'toLongArray'

    // ERROR: no direct toUIntArray() on UIntRange
    val e = (1u..7u).toUIntArray()  // KSWIFTK-SEMA-0024: unresolved member function 'toUIntArray'

    // ERROR: no direct toUIntArray() on UIntProgression
    val f = (1u..7u step 2).toUIntArray()  // KSWIFTK-SEMA-0024: unresolved member function 'toUIntArray'

    // ERROR: no direct toULongArray() on ULongRange
    val g = (1uL..7uL).toULongArray()  // KSWIFTK-SEMA-0024: unresolved member function 'toULongArray'

    // ERROR: no direct toULongArray() on ULongProgression
    val h = (1uL..7uL step 2).toULongArray()  // KSWIFTK-SEMA-0024: unresolved member function 'toULongArray'

    // OK: the spec-correct idiom keeps working
    val ok = (1..7).toList().toIntArray()
    println(ok.size)
}
