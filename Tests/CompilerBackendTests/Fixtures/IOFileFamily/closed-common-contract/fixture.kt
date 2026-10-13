import kotlinx.io.*
import kotlinx.io.files.*
import kotlin.random.Random

// Candidate safety policy follows pinned common RawSource/RawSink documentation.
// Upstream Native 0.9.1 closed-flush/read differ; this is deliberately not a
// JVM/Native implementation differential expectation. See closed-safety-ledger.json.
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
