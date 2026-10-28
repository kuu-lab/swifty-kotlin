@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    // KUU-3625: flatMapLatestRuntime's external bridge is
    // (flowHandle, mapperFnPtr, outThrown) — the suspend transform crosses
    // the ABI as a single boxed function value.
    println(flowOf(1).flatMapLatest { flowOf(it) }.toList())
    println(flowOf(1, 2).flatMapLatest { flowOf(it, it * 10) }.toList())

    // Capturing transform: the boxed suspend value carries the environment.
    val factor = 100
    println(flowOf(3).flatMapLatest { flowOf(it, it * factor) }.toList())
}
