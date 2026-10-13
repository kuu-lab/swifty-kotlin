// KUU-1359: iterator {} builder blocks that capture external variables used
// to panic at runtime (kk_array_get_inbounds) because the builder call dropped
// the lambda's closure environment and the CPS launcher bound its arguments in
// the wrong order.
fun main() {
    val values = listOf(1)
    println(iterator<Int> { yield(values[0]) }.asSequence().toList())

    val single = 7
    println(iterator<Int> { yield(single) }.asSequence().toList())

    val a = 1
    val b = 2
    val c = 3
    println(iterator<Int> { yield(a); yield(b); yield(c) }.asSequence().toList())

    val head = 5
    val tail = listOf(6, 7)
    val more = 8
    println(iterator<Int> { yield(head); yieldAll(tail); yield(more) }.asSequence().toList())

    val base = listOf(1)
    println(iterator<Int> {
        yield(base[0])
        yieldAll(iterator<Int> { yield(base[0] + 10); yield(base[0] + 20) })
        yield(base[0] + 30)
    }.asSequence().toList())

    for (x in iterator<Int> { yield(values[0]); yieldAll(values); yield(3) }) {
        println(x)
    }
}
