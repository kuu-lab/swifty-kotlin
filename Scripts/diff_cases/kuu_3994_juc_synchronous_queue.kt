import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.SynchronousQueue
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import java.lang.Thread

// KUU-3994: java.util.concurrent.SynchronousQueue — zero-capacity handoff.
// Blocking calls rendezvous with worker threads (self-synchronizing); the
// offer-with-waiting-consumer checks retry briefly so the result does not
// depend on thread scheduling. Output is deterministic on both compilers.
fun main() {
    val q = SynchronousQueue<String>()
    val box = LinkedBlockingQueue<String>()

    // put() blocks until a consumer take()s; take() blocks until a producer put()s.
    val producer = thread {
        q.put("hello")
        box.put("put-done")
    }
    println(q.take())          // hello
    println(box.take())        // put-done
    producer.join()

    // offer() succeeds once a consumer is parked; the retry loop only covers
    // scheduling, the handoff itself is what is asserted.
    val consumer = thread {
        box.put("got:" + q.poll(3000, TimeUnit.MILLISECONDS))
    }
    var offered = false
    var tries = 0
    while (!offered && tries < 100) {
        offered = q.offer("offer-val")
        tries++
        if (!offered) Thread.sleep(10)
    }
    println(offered)                    // true
    println(box.take())                 // got:offer-val
    consumer.join()

    // poll(timeout) receives from a blocked producer.
    val p = thread {
        q.put("p1")
        box.put("p-put-done")
    }
    println(q.poll(2000, TimeUnit.MILLISECONDS))  // p1
    println(box.take())                          // p-put-done
    p.join()

    // offer(timeout) hands off to a blocked consumer.
    val c3 = thread {
        box.put("c3:" + q.take())
    }
    var offered3 = false
    var tries3 = 0
    while (!offered3 && tries3 < 100) {
        offered3 = q.offer("timed-offer", 500, TimeUnit.MILLISECONDS)
        tries3++
        if (!offered3) Thread.sleep(10)
    }
    println(offered3)                 // true
    println(box.take())               // c3:timed-offer
    c3.join()

    // Sequential handoffs stay FIFO per rendezvous.
    var ok = true
    for (i in 0 until 5) {
        val prod = thread { q.put("item$i") }
        val cons = thread { box.put(q.take()) }
        val got = box.take()
        if (got != "item$i") ok = false
        prod.join(); cons.join()
    }
    println(ok)   // true

    // Concurrent producers and consumers: every put meets a take.
    val qi = SynchronousQueue<Int>()
    val results = LinkedBlockingQueue<Int>()
    val producers = mutableListOf<Thread>()
    val consumers = mutableListOf<Thread>()
    for (i in 0 until 3) {
        producers.add(thread { repeat(3) { qi.put(i * 10) } })
        consumers.add(thread { repeat(3) { results.put(qi.take()) } })
    }
    for (t in producers) t.join()
    for (t in consumers) t.join()
    var sum = 0
    repeat(9) { sum += results.take() }
    println(sum)   // 90 — 3 producers x 3 puts of {0,10,20}

    // The queue never stores elements: the whole Collection view is empty.
    println(q.size)                 // 0
    println(q.isEmpty())            // true
    println(q.remainingCapacity())  // 0
    println(q.peek())               // null
    println(q.drainTo(mutableListOf<String>()))  // 0
    println(q.toString())           // []
    println(q.iterator().hasNext()) // false
    println(q.contains("x"))        // false
    println(q.remove("x"))          // false
    println(q.removeAll(listOf("x")))   // false
    println(q.retainAll(listOf("x")))   // false
    q.clear()
    println("cleared")
    try { q.element() } catch (e: NoSuchElementException) { println("nsee") }
    try { q.remove() } catch (e: NoSuchElementException) { println("nsee2") }
    try { q.add("z") } catch (e: IllegalStateException) { println("ise:" + e.message) }
    try { q.addAll(listOf("a")) } catch (e: IllegalStateException) { println("ise2") }
    println(q.addAll(emptyList<String>()))  // false
    println(q.poll())               // null
    println(q.offer("solo"))        // false — no consumer waiting
    println(q.poll(30, TimeUnit.MILLISECONDS))  // null — timed out

    // Null elements are rejected like the JDK.
    val nq = SynchronousQueue<String?>()
    try { nq.offer(null); println("no-npe") } catch (e: NullPointerException) { println("npe") }
    try { nq.put(null); println("no-npe2") } catch (e: NullPointerException) { println("npe2") }
    println(nq.poll(10, TimeUnit.MILLISECONDS))   // null

    println("DONE")
}
