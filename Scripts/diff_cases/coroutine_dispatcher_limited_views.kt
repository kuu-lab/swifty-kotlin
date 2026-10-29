import kotlinx.coroutines.*
import kotlin.coroutines.ContinuationInterceptor

// KUU-2687 / KUU-2770: limitedParallelism view semantics — deterministic
// identity, nested toString names, and rejection parity with kotlinx.
// Dispatchers.Main behavior is exercised in KSwiftK tests instead: on JVM it
// resolves to MissingMainCoroutineDispatcher and calling any member throws.
fun main() = runBlocking {
    // Views are distinct dispatcher objects.
    println(Dispatchers.Default.limitedParallelism(1) === Dispatchers.Default)
    println(Dispatchers.IO.limitedParallelism(2) === Dispatchers.IO)
    val view1 = Dispatchers.Default.limitedParallelism(1)
    // A named parent makes the view independent of the JVM scheduler's
    // processor-dependent optimization for Dispatchers.Default.
    val namedParent = Dispatchers.Default.limitedParallelism(4, "named-base")
    // Nested views: a request no tighter than the stored limit returns this.
    println(view1.limitedParallelism(1) === view1)
    println(view1.limitedParallelism(3) === view1)
    // A tighter nested view is a new object.
    println(namedParent.limitedParallelism(2) === namedParent)
    // toString parity: "$dispatcher.limitedParallelism($parallelism)".
    println(view1.toString())
    println(namedParent.limitedParallelism(2).toString())
    println(namedParent.limitedParallelism(3).limitedParallelism(2).toString())
    println(Dispatchers.Default.limitedParallelism(1, "named-view").toString())
    // Nominal checks.
    println(view1 is CoroutineDispatcher)
    println(view1 is ContinuationInterceptor)
    println(Dispatchers.Main is MainCoroutineDispatcher)
    // Rejections keep upstream messages.
    try { Dispatchers.Unconfined.limitedParallelism(1) }
    catch (e: UnsupportedOperationException) { println(e.message) }
    try { Dispatchers.Default.limitedParallelism(0) }
    catch (e: IllegalArgumentException) { println(e.message) }
    try { Dispatchers.Default.limitedParallelism(-3) }
    catch (e: IllegalArgumentException) { println(e.message) }
    // Context element identity: the view survives a +/get round trip.
    val ctx = view1 + CoroutineName("c")
    println(ctx[ContinuationInterceptor] === view1)
    // Actual scheduling through the view still runs and resumes.
    println(withContext(view1) { "v1-resume" })
    println(withContext(Dispatchers.IO.limitedParallelism(2)) { "io2" })
}
