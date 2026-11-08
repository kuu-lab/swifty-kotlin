import java.util.*
import java.util.concurrent.*
import java.util.function.Supplier
import java.util.logging.*

enum class Color { RED, GREEN, BLUE }

fun <T> awaitDone(cf: CompletableFuture<T>): T {
    while (!cf.isDone) Thread.sleep(5)
    return cf.get()
}

fun main() {
    val v = Vector<String>()
    v.add("x")
    v.add("y")
    v.add("z")
    println(v.firstElement())
    println(v.lastElement())
    try {
        Vector<Int>().firstElement()
    } catch (e: Exception) {
        println("empty-first:${e::class.simpleName}")
    }
    println(v.elements().hasMoreElements())

    val ex = Executors.newScheduledThreadPool(2)
    ex.shutdown()
    println(ex.isShutdown)

    val f = CompletableFuture.supplyAsync(Supplier { 40 + 2 })
    println(awaitDone(f))
    val g = CompletableFuture.completedFuture(7)
    println(g.get())
    var accepted = ""
    g.thenAccept { accepted = "acc:$it" }
    Thread.sleep(50)
    println(accepted)

    val src = mapOf(Color.RED to "r", Color.BLUE to "b")
    val em = EnumMap<Color, String>(src)
    println(em[Color.RED])
    println(em.size)

    val lg = Logger.getGlobal()
    println(lg.name)
    println(Level.INFO.name)
    println(Level.SEVERE.intValue())
    println(Level.parse("FINE").name)
}
