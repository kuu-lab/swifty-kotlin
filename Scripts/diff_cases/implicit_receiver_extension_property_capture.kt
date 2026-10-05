import java.io.File

class Box(val raw: Int)

val Box.doubled: Int
    get() = raw * 2

val File.label: String
    get() = name

fun main() {
    Box(21).run {
        println(doubled)
        listOf(1, 2).forEach { println(doubled + it) }
        val read = { doubled }
        println(read())
    }
    File("receiver.txt").run {
        println(label)
        listOf(1, 2).forEach { println(label) }
        val read = { label }
        println(read())
    }
}
