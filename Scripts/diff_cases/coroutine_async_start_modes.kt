import kotlinx.coroutines.*

// `async(start = ...)` must honour the requested CoroutineStart.
// The overload did not exist at all: `async(start = CoroutineStart.LAZY) { 42 }`
// failed to type-check with KSWIFTK-SEMA-0002, because only a single-argument
// `async(block:)` was registered and the lowering's start-mode dispatch was
// reachable from `launch` alone.
//
// `Deferred` carries no isCompleted/isActive stub in this compiler, so each mode
// is distinguished by print ordering rather than by querying the handle: a body
// that has already run prints before the marker following `yield()`, and one
// that has not prints after it.

fun main() = runBlocking {
    // UNDISPATCHED runs the body inline on the calling thread until its first
    // suspension, so "undispatched1" precedes "after undispatched async".
    val undispatched = async(start = CoroutineStart.UNDISPATCHED) {
        println("undispatched1")
        yield()
        println("undispatched2")
        11
    }
    println("after undispatched async")
    println("undispatched result: ${undispatched.await()}")

    // Capture-bearing UNDISPATCHED block: same inline start, but routed through
    // the launcher-thunk (continuation) shape instead of the bare functionID.
    val capture = "capture"
    val undispatchedCapturing = async(start = CoroutineStart.UNDISPATCHED) {
        println("undispatched $capture")
        22
    }
    println("after capturing undispatched async")
    println("capturing undispatched result: ${undispatchedCapturing.await()}")

    // DEFAULT schedules the body right away, so a single yield is enough to run
    // it -- no await needed. Under LAZY it would not have started at all.
    val default = async(start = CoroutineStart.DEFAULT) {
        println("default body")
        33
    }
    println("after default async")
    yield()
    println("default marker after yield")
    println("default result: ${default.await()}")

    // ATOMIC likewise starts without being awaited.
    val atomic = async(start = CoroutineStart.ATOMIC) {
        println("atomic body")
        44
    }
    println("after atomic async")
    yield()
    println("atomic marker after yield")
    println("atomic result: ${atomic.await()}")

    // LAZY defers until await(): its body prints after the marker, not before.
    val lazy = async(start = CoroutineStart.LAZY) {
        println("lazy body")
        55
    }
    println("after lazy async")
    yield()
    println("lazy marker after yield")
    println("lazy result: ${lazy.await()}")

    // Capture-bearing LAZY: same deferral through the continuation shape.
    val lazyCapture = "lazy capture"
    val lazyCapturing = async(start = CoroutineStart.LAZY) {
        println("body with $lazyCapture")
        66
    }
    println("after capturing lazy async")
    yield()
    println("capturing lazy marker after yield")
    println("capturing lazy result: ${lazyCapturing.await()}")
}
