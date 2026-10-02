fun main() {
    var sum = 0
    repeat(5) { if (it == 3) return@repeat; sum += it }
    println(sum)
    println("after")
    for (i in 0 until 3) repeat(2) { if (it == 1) return@repeat; print("$i") }
    println()
    var t = 0
    repeat(4) {
        try {
            if (it == 1) return@repeat
            t += 10
        } finally {
            t += 1
        }
    }
    println(t)
}
