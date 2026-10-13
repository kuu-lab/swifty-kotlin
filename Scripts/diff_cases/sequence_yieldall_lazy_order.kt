// BUG-255 regression: Verify that yieldAll(sequence) pulls from the source sequence
// lazily, interleaved with the outer builder's own execution, rather than
// eagerly draining it up front. If yieldAll materialized the whole inner
// sequence before yielding, "inner:3" would print before we stop early.
//
// Expected output (matches real kotlinc):
//   start
//   outer:before
//   inner:1
//   1
//   inner:2
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
