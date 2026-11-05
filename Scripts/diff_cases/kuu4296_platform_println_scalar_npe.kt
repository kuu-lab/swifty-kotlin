// KUU-4296: platform `T!` returns passed to kotlin.io.println/print resolve to
// the JVM scalar overloads (println(Int) and friends), so an empty poll raises
// NPE through the platform null assertion like kotlinc, instead of printing
// "null" through the Any? fallback. Nullable Any?/String? destinations still
// accept the platform null without a check on both compilers.
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.PriorityQueue

fun takeAny(value: Any?) { println("any:$value") }

fun main() {
    val emptyInts = ConcurrentLinkedQueue<Int>()

    // Empty Int platform value through println -> println(Int) -> NPE.
    try {
        println(emptyInts.poll())
        println("unexpected:println-int")
    } catch (e: NullPointerException) {
        println("npe:println-poll")
    }

    // Same divergence through print.
    try {
        print(emptyInts.poll())
        println("unexpected:print-int")
    } catch (e: NullPointerException) {
        println("npe:print-poll")
    }

    // PriorityQueue.poll() on an empty queue -> NPE on the scalar path.
    val emptyPq = PriorityQueue<Int>()
    try {
        println(emptyPq.poll())
        println("unexpected:pq-poll")
    } catch (e: NullPointerException) {
        println("npe:pq-poll")
    }

    // Non-empty platform values still print their scalar contents.
    val ints = ConcurrentLinkedQueue<Int>()
    ints.add(42)
    println(ints.poll())
    println(ints.poll() == null)

    // Any? destinations keep the platform null: kotlinc inserts no
    // checkNotNull for a nullable parameter.
    takeAny(emptyInts.poll())
    val anyValue: Any? = emptyInts.poll()
    println("any-local:$anyValue")

    // A platform String prints "null" on both compilers (no scalar overload
    // applies, and the String-specialized println is bypassed for `T!`).
    val strings = ConcurrentLinkedQueue<String>()
    println(strings.poll())

    // Other scalar families follow the same rule.
    val bools = ConcurrentLinkedQueue<Boolean>()
    try {
        println(bools.poll())
        println("unexpected:bool-poll")
    } catch (e: NullPointerException) {
        println("npe:bool-poll")
    }
    val longs = ConcurrentLinkedQueue<Long>()
    longs.add(7L)
    println(longs.poll())
}
