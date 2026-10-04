import kotlin.RequiresOptIn.Level

fun main() {
    println(Level.entries != null)
    println(Level.valueOf("WARNING"))
    println(Level.values()[0])
    println(Level.values()[1])
}
