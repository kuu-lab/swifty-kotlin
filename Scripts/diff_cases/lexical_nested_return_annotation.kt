// KUU-1305: Resolve qualified nested return annotations in the enclosing class.
class Ch {
    private sealed interface Slot {
        data class Closed(val cause: Throwable?) : Slot
    }
    private fun closed(cause: Throwable?): Slot.Closed = Slot.Closed(cause)
}
fun main() { println("ok") }
