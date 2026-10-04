fun describe(v: Any): String = when (v) {
    is IntRange -> "IntRange ${v.first}..${v.last}"
    is LongRange -> "LongRange"
    is CharRange -> "CharRange"
    is UIntRange -> "UIntRange"
    is IntProgression -> "IntProgression"
    else -> "other"
}

fun main() {
    val r = 1..5
    println(r is IntRange)
    println(r is IntProgression)
    println(r is ClosedRange<*>)
    println(r is OpenEndRange<*>)
    println(r is Iterable<*>)
    println(r is List<*>)

    val ur = 1u..5u
    println(ur is UIntRange)
    println(ur is UIntProgression)
    println(ur is ClosedRange<*>)

    val lr = 1L..5L
    println(lr is LongRange)
    println(lr is LongProgression)

    val cr = 'a'..'z'
    println(cr is CharRange)
    println(cr is CharProgression)

    val ulr = 1uL..5uL
    println(ulr is ULongRange)
    println(ulr is ULongProgression)

    val prog = 1..10 step 2
    println(prog is IntProgression)
    println(prog is IntRange)

    val down = 10 downTo 1
    println(down is IntProgression)
    println(down is IntRange)

    val until = 1 until 5
    println(until is IntRange)

    val dr = 1.0..5.0
    println(dr is ClosedFloatingPointRange<*>)
    println(dr is ClosedRange<*>)

    // casts
    val anyR: Any = 1..5
    println(anyR is IntRange)
    println(anyR as IntRange)
    println(anyR as? IntRange)
    println(anyR as? LongRange)
    println(anyR as? String)

    // smart cast
    if (anyR is IntRange) {
        println(anyR.first + anyR.last)
    }

    // when over ranges
    println(describe(1..5))
    println(describe(1L..5L))
    println(describe('a'..'z'))
    println(describe(1u..5u))
    println(describe(1..10 step 3))
    println(describe("not a range"))

    // filterIsInstance
    val mixed: List<Any> = listOf(1..5, "x", 1L..3L, 7)
    println(mixed.filterIsInstance<IntRange>())
    println(mixed.filterIsInstance<ClosedRange<*>>())

    // range iterator answers the Iterator interface
    val it = (1..5).iterator()
    println(it is Iterator<*>)
    println(it is Iterable<*>)
    val itAny: Any = it
    val cast = itAny as Iterator<*>
    println(cast.hasNext())
    println(cast.next())
}
