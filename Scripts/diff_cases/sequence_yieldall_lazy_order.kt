// SKIP-DIFF (DEBT-DIFF-010): pre-existing runtime laziness bug (BUG-255),
// unrelated to KSP-1519 itself (Sources/Runtime/ untouched by that PR).
//
// KSP-1519: Verify that yieldAll(sequence) pulls from the source sequence
// lazily, interleaved with the outer builder's own execution, rather than
// eagerly draining it up front. If yieldAll materialized the whole inner
// sequence before yielding, "inner:3" would print before we stop early.
//
// Expected (real kotlinc, the oracle to restore once BUG-255 is fixed):
//   start
//   outer:before
//   inner:1
//   1
//   inner:2
//   2
//   stop early
//
// Actual (kswiftc, BUG-255): the whole inner sequence and the rest of the
// outer builder's body run synchronously before the first next() returns:
//   start
//   outer:before
//   inner:1
//   inner:2
//   inner:3
//   outer:after
//   1
//   2
//   stop early
fun main() {
    val inner = sequence {
        println("inner:1")
        yield(1)
        println("inner:2")
        yield(2)
        println("inner:3")
        yield(3)
    }
    val outer = sequence {
        println("outer:before")
        yieldAll(inner)
        println("outer:after")
        yield(99)
    }
    val iter = outer.iterator()
    println("start")
    println(iter.next())
    println(iter.next())
    println("stop early")
}
