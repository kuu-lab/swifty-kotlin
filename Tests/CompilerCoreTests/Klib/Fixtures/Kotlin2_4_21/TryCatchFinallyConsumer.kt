import klibexceptions.*

fun main() {
    println(guarded(1))
    println(guarded(0))
    println(guarded(2))
    println(nested())
    try {
        guarded(4)
    } catch (error: NumberFormatException) {
        println(error.message)
    }
    try {
        guarded(5)
    } catch (error: IllegalStateException) {
        println(error.message)
    }
    println(earlyReturn(true))
    println(earlyReturn(false))
    println(loopExits())
}
