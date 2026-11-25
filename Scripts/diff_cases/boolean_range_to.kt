// DIFF_JVM
fun main() {
    val b = true..false
    println(b)
    println(b.isEmpty())
    println(true in b)
    println(false in b)
    val e = false..true
    println(e.isEmpty())
    println(false in e)
    println(true in e)
}
