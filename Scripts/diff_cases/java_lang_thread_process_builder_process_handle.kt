import java.lang.ProcessBuilder
import java.lang.ProcessHandle
import java.lang.Thread

fun main() {
    val current = Thread.currentThread()
    println(current.name)
    println(current.id > 0L)
    println(current.isAlive)

    val worker = Thread { println("run") }
    println(worker.isAlive)
    worker.start()
    worker.join()
    println(worker.isAlive)
    println(Thread.activeCount())
    Thread.sleep(1)

    val builder = ProcessBuilder("echo", "hi")
    println(builder.command().joinToString(","))
    val process = ProcessBuilder("true").start()
    println(process.waitFor())
    println(process.exitValue())
    println(process.isAlive)
    println(process.pid() > 0L)
    println(ProcessHandle.current().pid() > 0L)
}
