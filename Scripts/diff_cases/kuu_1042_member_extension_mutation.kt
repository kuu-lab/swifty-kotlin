// KUU-1042: member extension mutation and calls keep both receivers distinct.
class B {
    var seconds: Int = 0
    fun readSeconds(): Int = seconds
}

class P {
    var seconds: Int = 100
    fun B.handleToken(chunk: String) { seconds = chunk.toInt() }
    fun go(b: B) = b.handleToken("5")

    fun B.update(): Int {
        seconds += 2
        this.seconds = readSeconds() + 3
        this@P.seconds += 10
        return readSeconds()
    }

    fun goUpdate(b: B): Int = b.update()
}

fun main() {
    val b = B()
    val p = P()
    p.go(b)
    println(b.seconds)
    println(p.seconds)
    println(p.goUpdate(b))
    println(b.seconds)
    println(p.seconds)
}
