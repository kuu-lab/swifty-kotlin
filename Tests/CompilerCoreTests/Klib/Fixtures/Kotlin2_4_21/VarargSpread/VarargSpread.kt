package klibvarargspread

fun total(vararg nums: Int) = nums.sum()

fun forward(xs: IntArray) = total(1, *xs, 4)

private fun ints(vararg values: Int): IntArray = values

private var trace = 0

private fun traceInt(value: Int): Int {
    trace = trace * 10 + value
    return value
}

private fun traceSpread(marker: Int, values: IntArray): IntArray {
    traceInt(marker)
    return values
}

fun forwardInOrder(xs: IntArray, ys: IntArray): IntArray {
    trace = 0
    return ints(traceInt(1), *traceSpread(2, xs), traceInt(3), *traceSpread(4, ys), traceInt(5))
}

fun evaluationOrder(): Int = trace

fun copySpread(xs: IntArray): IntArray = ints(*xs)

private fun refs(vararg values: Any?): Array<out Any?> = values

fun forwardRefs(xs: Array<String?>, ys: Array<Any?>): Array<out Any?> =
    refs("head", *xs, 7, *ys, '!', null)
