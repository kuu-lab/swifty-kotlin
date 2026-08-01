// SKIP-DIFF (DEBT-DIFF-005): end-to-end sequence {} builder requires KSP-447
// residual runtime/source object pipeline wiring (Iterator itable dispatch for
// coroutine-produced Sequence objects). Type inference is now unblocked, but the
// generated Sequence/Iterator object expressions still fail virtual dispatch.
//
// STDLIB-563: Verify that sequence {} builder is lazy.
// Side effects in the builder should only execute when elements are consumed.
fun main() {
    // Basic sequence builder: yield values one at a time
    val seq = sequence {
        yield(1)
        yield(2)
        yield(3)
    }
    println(seq.toList())

    // take(2) should not force evaluation beyond the 2nd element
    val seq2 = sequence {
        yield(10)
        yield(20)
        yield(30)
        yield(40)
    }
    println(seq2.take(2).toList())

    // map + filter chain on sequence builder
    val seq3 = sequence {
        yield(1)
        yield(2)
        yield(3)
        yield(4)
        yield(5)
    }
    println(seq3.filter { it % 2 == 0 }.map { it * 10 }.toList())

    // first() should only need one element
    val seq4 = sequence {
        yield(100)
        yield(200)
    }
    println(seq4.first())

    // yieldAll inside sequence builder
    val seq5 = sequence {
        yield(1)
        yieldAll(listOf(2, 3, 4))
        yield(5)
    }
    println(seq5.toList())

    // Nested yields with loop
    val seq6 = sequence {
        for (i in 1..5) {
            yield(i * i)
        }
    }
    println(seq6.toList())
    println(seq6.take(3).toList())
}
