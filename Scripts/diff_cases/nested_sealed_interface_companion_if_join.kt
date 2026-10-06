// KUU-1288: infer nested companion properties before checking enclosing functions.
import Outer.Inner.Slot as DeepSlot

class Ch {
    private sealed interface Slot {
        companion object { val CLOSED = Closed(null) }
        data object Empty : Slot
        data class Closed(val cause: Throwable?) : Slot
    }

    fun close(cause: Throwable?): Boolean {
        val c = if (cause != null) Slot.Closed(cause) else Slot.CLOSED
        return c.cause == cause
    }
}

interface Slot2 {
    companion object { val CLOSED = Closed(null) }
    data class Closed(val cause: Throwable?) : Slot2
}

class Outer {
    fun value() = DeepSlot.VALUE
    class Inner {
        interface Slot {
            companion object { val VALUE = 42 }
        }
    }
}

fun main() {
    val ch = Ch()
    println(ch.close(null))
    println(ch.close(Exception("closed")))
    val cause: Throwable? = null
    val c = if (cause != null) Slot2.Closed(cause) else Slot2.CLOSED
    println(c.cause == cause)
    println(Outer().value())
}
