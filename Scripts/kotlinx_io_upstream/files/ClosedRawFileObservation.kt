import kotlinx.io.*
import kotlinx.io.files.*
import kotlin.random.Random

// A common DOCUMENTED contract probe, not a claim that current JVM/Native
// upstream implementations return these exact exception types after close.
// The current JVM IOException behavior needs an explicit differential policy.
private fun observe(label: String, operation: () -> Unit) {
    try {
        operation()
        println("$label:NO_EXCEPTION")
    } catch (failure: Throwable) {
        println("$label:${failure::class.simpleName}")
    }
}

fun main() {
    val path = Path(SystemTemporaryDirectory, "kswiftk-b06-closed-" + Random.nextInt(1, 1000000000))
    try {
        val sink = SystemFileSystem.sink(path)
        sink.close()
        sink.close()
        observe("closed-write-zero") { sink.write(Buffer(), 0) }
        observe("closed-write-one") { sink.write(Buffer().also { it.writeByte(1) }, 1) }
        observe("closed-flush") { sink.flush() }
        val source = SystemFileSystem.source(path)
        source.close()
        source.close()
        observe("closed-read-zero") { source.readAtMostTo(Buffer(), 0) }
        observe("closed-read-one") { source.readAtMostTo(Buffer(), 1) }
    } finally {
        SystemFileSystem.delete(path, mustExist = false)
    }
}
