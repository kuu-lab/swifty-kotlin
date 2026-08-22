fun main() {
    val sized = IntArray(3)
    println(sized.size)
    println(sized[0])

    val initialized = IntArray(4) { (it + 1) * 2 }
    println(initialized.size)
    println(initialized[0])
    println(initialized[3])
    println(IntArray(0) { 42 }.size)
}
