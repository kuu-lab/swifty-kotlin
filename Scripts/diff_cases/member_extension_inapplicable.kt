class Box {
    fun append(a: Int, b: Int, c: Int): String = "member"
    fun score(value: Int): Int = value + 1
}

fun Box.append(value: Int): String = "extension"
fun Box.score(value: String): Int = score(7)

fun main() {
    val box = Box()
    println(box.append(1))
    println(box.append(1, 2, 3))
    println(box.score("x"))
    println(box.score(1))
}
