fun main() {
    var sum = 0
    repeat(5) lbl@{
        if (it == 3) return@lbl
        sum += it
    }
    println(sum)
    println("after")
}
