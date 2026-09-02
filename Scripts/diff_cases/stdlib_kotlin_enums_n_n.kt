import kotlin.enums.enumEntries

enum class Color { RED, GREEN }

fun main() {
    val entries = enumEntries<Color>()
    println(entries.size)
    println(entries[0])
    println(entries[1])
    println(entries === Color.entries)
    println(entries.contains(Color.RED))
    println(entries.indexOf(Color.GREEN))
    try {
        entries[2]
    } catch (e: IndexOutOfBoundsException) {
        println("IndexOutOfBoundsException")
    }
}
