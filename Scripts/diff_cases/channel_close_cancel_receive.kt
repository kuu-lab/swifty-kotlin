// NOTE: Requires kotlinx-coroutines on classpath.
// KUU-1404: receive() on a closed/cancelled channel must throw
// (ClosedReceiveChannelException / CancellationException) instead of
// returning the element-type default value, and send() on a closed
// channel must throw ClosedSendChannelException.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

fun main() = runBlocking {
    // Test 1: closed + drained channel -> ClosedReceiveChannelException.
    val ch = Channel<Int>(3)
    ch.send(1)
    println(ch.receive()) // 1
    ch.send(41)
    ch.close()
    println(ch.receive()) // 41: buffered elements still drain
    try {
        println(ch.receive())
        println("closed-receive-returned")
    } catch (e: ClosedReceiveChannelException) {
        println("closed-receive-threw-CRCE")
    } catch (e: Throwable) {
        println("closed-receive-threw-other")
    }

    // Test 2: cancelled channel -> CancellationException.
    val ch2 = Channel<Int>(1)
    ch2.cancel()
    try {
        println(ch2.receive())
        println("cancelled-receive-returned")
    } catch (e: CancellationException) {
        println("cancelled-receive-threw-CE")
    } catch (e: Throwable) {
        println("cancelled-receive-threw-other")
    }

    // Test 3: cancelled channel discards buffered elements.
    val ch3 = Channel<Int>(4)
    ch3.send(9)
    ch3.cancel()
    try {
        println(ch3.receive())
        println("cancelled-buffered-receive-returned")
    } catch (e: CancellationException) {
        println("cancelled-buffered-receive-threw-CE")
    } catch (e: Throwable) {
        println("cancelled-buffered-receive-threw-other")
    }

    // Test 4: send on closed channel -> ClosedSendChannelException.
    val ch4 = Channel<Int>(2)
    ch4.close()
    try {
        ch4.send(5)
        println("closed-send-returned")
    } catch (e: ClosedSendChannelException) {
        println("closed-send-threw-CSCE")
    } catch (e: Throwable) {
        println("closed-send-threw-other")
    }

    // Test 5: ClosedReceiveChannelException is a NoSuchElementException
    // (kotlinx-coroutines JVM extends java.util.NoSuchElementException).
    val ch5 = Channel<Int>(0)
    ch5.close()
    try {
        ch5.receive()
        println("superclass-catch-returned")
    } catch (e: NoSuchElementException) {
        println("closed-receive-caught-as-NSEE")
    } catch (e: Throwable) {
        println("superclass-catch-threw-other")
    }

    // Test 6: for-in iteration still terminates cleanly after close.
    val ch6 = Channel<Int>(2)
    ch6.send(10)
    ch6.send(20)
    ch6.close()
    var sum = 0
    for (v in ch6) {
        sum += v
    }
    println("sum=$sum")

    // Test 7: for-in over a cancelled channel throws CancellationException
    // from hasNext() (JVM parity) instead of silently ending the loop.
    val ch7 = Channel<Int>(2)
    ch7.send(1)
    ch7.cancel()
    try {
        for (v in ch7) {
            println("iter-got-$v")
        }
        println("cancelled-for-returned")
    } catch (e: CancellationException) {
        println("cancelled-for-threw-CE")
    } catch (e: Throwable) {
        println("cancelled-for-threw-other")
    }

    // Test 8: user-constructed closed-channel exceptions round-trip through
    // the runtime bridges and remain catchable by type.
    try {
        throw ClosedReceiveChannelException("manual")
    } catch (e: ClosedReceiveChannelException) {
        println("manual-crce-caught")
    } catch (e: Throwable) {
        println("manual-crce-other")
    }
    try {
        throw ClosedSendChannelException("manual")
    } catch (e: ClosedSendChannelException) {
        println("manual-csce-caught")
    } catch (e: Throwable) {
        println("manual-csce-other")
    }
    println("done")
}
