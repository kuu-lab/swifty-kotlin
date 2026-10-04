class Box(var n: Int, var s: String)
class Holder(val box: Box) {
    fun bump(): Int {
        this.box.n += 5
        return box.n
    }
}

var sideEffectCount = 0
fun getBox(b: Box): Box {
    sideEffectCount += 1
    return b
}

fun bumpExternal(b: Box): Int {
    b.n += 1
    return b.n
}

fun main() {
    println(Holder(Box(1, "hi")).bump())

    val box = Box(1, "hi")

    box.n += 5
    println(box.n)

    box.n++
    println(box.n)
    box.n--
    println(box.n)

    box.n -= 2
    box.n *= 3
    box.n /= 2
    box.n %= 4
    println(box.n)

    box.s += " there"
    println(box.s)

    // Receiver expression must be evaluated exactly once.
    getBox(box).n += 100
    println(box.n)
    println(sideEffectCount)

    println(bumpExternal(box))
    println(box.n)
}
