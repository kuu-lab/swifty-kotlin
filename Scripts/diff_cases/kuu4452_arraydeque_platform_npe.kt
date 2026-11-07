// KUU-4452: a bundled java.util platform `T!` result used in a non-null
// position raises the JVM `checkNotNullExpressionValue` NPE
// `"<call>(...) must not be null"` — catchable, so `e.message` is
// observable. The same empty-deque methods reached through nullable or
// discarded results then keep throwing NoSuchElementException like the JVM.
import java.util.*

fun main() {
    val dq = ArrayDeque<Int>()
    try {
        println(dq.poll())
        println("unexpected:poll-print")
    } catch (e: NullPointerException) {
        println("poll:${e.message}")
    }
    try {
        println(dq.peek())
        println("unexpected:peek-print")
    } catch (e: NullPointerException) {
        println("peek:${e.message}")
    }
    try {
        val v: Int = dq.pollFirst()
        println("unexpected:$v")
    } catch (e: NullPointerException) {
        println("pollFirst:${e.message}")
    }

    // A platform value parked in a local keeps the plain message-less NPE,
    // matching the JVM (the diagnostic only attaches to direct calls).
    val parked = dq.pollFirst()
    try {
        val v: Int = parked
        println("unexpected:$v")
    } catch (e: NullPointerException) {
        println("parked:${e.message}")
    }

    // `!!` still raises the plain NPE with no message.
    val bare: Int? = null
    try {
        println(bare!!)
    } catch (e: NullPointerException) {
        println("bang:${e.message}")
    }

    // Discarded / nullable poll results leave the deque usable: element(),
    // removeFirst(), remove(), pop() throw NoSuchElementException — the
    // catch the ticket expected.
    val dq2 = ArrayDeque<Int>()
    dq2.poll()
    try {
        println(dq2.element())
    } catch (e: Throwable) {
        println("element:${e::class.simpleName}")
    }
    dq2.peek()
    try {
        println(dq2.removeFirst())
    } catch (e: Throwable) {
        println("removeFirst:${e::class.simpleName}")
    }
    try {
        println(dq2.remove())
    } catch (e: Throwable) {
        println("remove:${e::class.simpleName}")
    }
    try {
        println(dq2.pop())
    } catch (e: Throwable) {
        println("pop:${e::class.simpleName}")
    }

    // Reference-typed poll prints null, then element() throws.
    val strings = ArrayDeque<String>()
    println("str-poll:${strings.poll()}")
    try {
        println(strings.element())
    } catch (e: Throwable) {
        println("str-element:${e::class.simpleName}")
    }
}
