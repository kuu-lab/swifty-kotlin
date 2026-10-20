object Log { var attempts = 0 }
object Failed {
    init { Log.attempts++; throw IllegalStateException("failed") }
    fun value(): Int = 1
}
enum class Broken { VALUE { init { Log.attempts++; throw IllegalStateException("entry") } } }
fun main() {
    for (i in 1..2) {
        try { println(Failed.value()) } catch (failure: Throwable) { println(Log.attempts) }
    }
    for (i in 1..2) {
        try { println(Broken.VALUE) } catch (failure: Throwable) { println(Log.attempts) }
    }
}
