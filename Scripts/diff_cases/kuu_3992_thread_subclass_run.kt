// KUU-3992: bundled java.lang.Thread is open and run() is overridable,
// matching java.lang.Thread on the JVM. Subclass dispatch through
// start()/join() must invoke the override on the spawned thread.
class NamedWorker(val label: String) : Thread() {
    override fun run() {
        println("run:$label:${Thread.currentThread().name}")
        println("self:${Thread.currentThread() === this}")
        println("alive-in-run:$isAlive")
    }
}

class DelegatingWorker(r: Runnable) : Thread(r) {
    override fun run() {
        println("before-delegate")
        super.run()
        println("after-delegate")
    }
}

fun main() {
    val w = NamedWorker("named")
    w.name = "worker-thread"
    println("before:${w.isAlive}")
    w.start()
    w.join()
    println("after:${w.isAlive}")

    val d = DelegatingWorker(Runnable { println("delegate-body") })
    d.start()
    d.join()

    val anon = object : Thread() {
        override fun run() { println("anon-body") }
    }
    anon.start()
    anon.join(5000L)
    println("anon-done:${anon.isAlive}")

    println("main-done")
}
