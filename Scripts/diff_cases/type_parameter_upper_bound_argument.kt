// KUU-1287: nested upper bounds must remain available at ordinary call sites.
class Host {
    interface Slot {
        interface Task : Slot
    }
    object Empty : Slot
    class Work : Slot.Task

    class Ref<T>(var value: T) {
        fun compareAndSet(expect: T, update: T): Boolean {
            if (value !== expect) return false
            value = update
            return true
        }
    }

    private val slot = Ref<Slot>(Empty)

    fun <T : Slot.Task> install(value: T): Boolean = slot.compareAndSet(slot.value, value)

    inline fun <reified T : Slot.Task> replace(ref: Ref<Slot>, value: T): Boolean =
        ref.compareAndSet(ref.value, value)

    inline fun <reified Expected : Slot.Task> clear(ref: Ref<Slot>): Boolean {
        val current = ref.value
        return current is Expected && ref.compareAndSet(current, Empty)
    }
}

fun main() {
    val host = Host()
    val work = Host.Work()
    println(host.install(work))
    val ref = Host.Ref<Host.Slot>(Host.Empty)
    println(host.replace(ref, work))
    println(host.clear<Host.Work>(ref))
    println(host.clear<Host.Work>(ref))
}
