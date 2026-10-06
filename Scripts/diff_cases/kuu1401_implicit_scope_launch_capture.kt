import kotlinx.coroutines.*
// Bare `launch {}`/`async {}` on the enclosing coroutine's implicit scope
// lowered its block with no receiver parameter — `this` binds through
// `coroutineScopeLambdaReceiverTypes` (`kk_coroutine_current_scope`) — so
// every suspend-fn parameter is a capture. The launcher rewrite reserved
// the LAST parameter slot for the receiver scope handle anyway, so the
// runtime overwrote the last capture: a `var` store wrote into the scope
// object (KSWIFTK-LINK-0003 panic) and a `val` read printed the raw box
// (`v=<object 0x…>`). The scope write must be parked one slot past the
// last capture instead.
fun main() = runBlocking {
    // var store into an outer local used to panic as an unhandled exception.
    var n = 0
    launch { n = 42 }.join()
    println("ok $n")

    // val read used to print the receiver scope box, not the captured value.
    val v = 7
    launch { println("v=$v") }.join()

    // More than one capture: the clobbered slot was the LAST one, so earlier
    // captures used to survive while the last printed a box / broke stores.
    val a = 1
    val b = 2
    launch { println("a=$a b=$b") }.join()

    // Same convention inside an explicit coroutineScope block.
    coroutineScope {
        var m = 5
        launch { m = 6 }.join()
        println("m=$m")
    }
}
