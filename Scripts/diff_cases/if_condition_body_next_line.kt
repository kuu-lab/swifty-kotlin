fun choose(a: Boolean, b: Boolean): Int {
    var w = if (a)
        if (b) 1
        else 2
    else 3
    return w
}

fun main() {
    println(choose(true, true))
    println(choose(true, false))
    println(choose(false, false))
}
