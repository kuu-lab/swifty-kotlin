fun main() {
    for (b in "HI".encodeToByteArray()) {
        println(b)
    }
    for (x in intArrayOf(10, 20, 30)) {
        println(x)
    }
    for (s in arrayOf("a", "b", "c")) {
        println(s)
    }
    for (x in IntArray(0)) {
        println(x)
    }
    println("empty done")
    for (x in intArrayOf(1, 2, 3, 4, 5)) {
        if (x == 2) continue
        if (x == 4) break
        println(x)
    }
}
