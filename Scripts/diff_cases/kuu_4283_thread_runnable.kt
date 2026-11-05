// KUU-4283: bundled java.lang.Thread implements java.lang.Runnable, matching
// the JVM (`public class Thread implements Runnable`). A Thread instance must
// be assignable to Runnable and runnable through Executor/FutureTask surfaces.
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit

fun label(r: Runnable): String = if (r is Thread) "thread" else "other"

fun main() {
    val t = Thread { println("thread-body") }
    val r: Runnable = t
    println(t is Runnable)
    println(r is Thread)
    println(label(t))
    println(label(Runnable { println("unused") }))

    val executor = Executors.newSingleThreadExecutor()
    executor.execute(t)
    executor.shutdown()
    println(executor.awaitTermination(30, TimeUnit.SECONDS))

    val task = FutureTask(t, "done")
    println(task.isDone)
    task.run()
    println(task.get())
    println(task.isDone)
}
