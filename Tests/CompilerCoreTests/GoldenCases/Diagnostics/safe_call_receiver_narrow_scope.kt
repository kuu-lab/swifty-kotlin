class Box(var v: Int = 0) {
    fun run(n: Int): Int = n + v
}

fun bangNarrowDoesNotEscape(flag: Boolean): Int {
    var y: Box? = null
    var x: Box? = Box()
    if (flag) { y = Box() }
    x?.run(y!!.v)
    return y.v
}

fun castNarrowDoesNotEscape(flag: Boolean): Int {
    var y: Box? = null
    var x: Box? = Box()
    if (flag) { y = Box() }
    x?.run((y as Box).v)
    return y.v
}

fun bangReceiverStillNarrows(y: Box?): Int {
    y!!?.run(0)
    return y.v
}

fun castReceiverStillNarrows(y: Box?): Int {
    (y as Box)?.run(0)
    return y.v
}
