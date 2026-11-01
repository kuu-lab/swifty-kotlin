class Seg(var shared: Boolean = false) {
    fun unsharedCopy(): Seg = Seg()
    fun tag(): Int = 7
}

// `x!!` on the right of `&&` narrows inside the then-body (KUU-3943).
fun andThen(offset: Long, rw: Boolean): Int {
    var next: Seg? = null
    if (offset >= 0) {
        next = Seg(true)
    }
    if (rw && next!!.shared) {
        return next.unsharedCopy().tag()
    }
    return 0
}

// `x!!` on the right of `||` narrows inside the else-body.
fun orElse(offset: Long, rw: Boolean): Int {
    var next: Seg? = null
    if (offset >= 0) {
        next = Seg(false)
    }
    if (rw || next!!.shared) {
        return 0
    }
    return next.unsharedCopy().tag() + 1
}

// `x!!` on the left of `&&` always runs: narrows into the else-body too.
fun leftAlways(offset: Long, rw: Boolean): Int {
    var next: Seg? = null
    if (offset >= 0) {
        next = Seg(false)
    }
    if (next!!.tag() > 0 && rw) {
        return 1
    }
    return next.unsharedCopy().tag() + 2
}

// Variable assigned inside both `if`/`else` branches (okio Buffer cursor shape).
fun bothBranches(offset: Long, rw: Boolean): Int {
    var next: Seg? = null
    if (offset >= 0) {
        next = Seg(true)
    } else {
        next = Seg(false)
    }
    if (rw && next!!.shared) {
        return next.unsharedCopy().tag() + 10
    }
    return 0
}

// `x!!` inside a `while` condition's `&&` narrows the loop body.
fun whileBody(offset: Long): Int {
    var next: Seg? = null
    if (offset >= 0) {
        next = Seg(false)
    }
    var i = 0
    while (i < 1 && next!!.tag() > 0) {
        i += next.unsharedCopy().tag() + 20
    }
    return i
}

fun main() {
    println(andThen(1, true))
    println(andThen(1, false))
    println(orElse(1, false))
    println(orElse(1, true))
    println(leftAlways(1, false))
    println(bothBranches(1, true))
    println(bothBranches(-1, true))
    println(whileBody(1))
}
