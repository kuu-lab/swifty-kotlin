import kotlinx.coroutines.CoroutineStart

fun main() {
    println(CoroutineStart.UNDISPATCHED)
    println(CoroutineStart.DEFAULT.name)
    println(CoroutineStart.LAZY.ordinal)
    println(CoroutineStart.ATOMIC.name)
    for (s in CoroutineStart.values()) {
        println("${s.name}:${s.ordinal}")
    }
    println(CoroutineStart.valueOf("UNDISPATCHED").ordinal)
    println(CoroutineStart.entries.size)
    println(CoroutineStart.entries[1].name)
}
