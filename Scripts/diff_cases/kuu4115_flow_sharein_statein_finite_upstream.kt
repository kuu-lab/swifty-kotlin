import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

// KUU-4115: shareIn/stateIn must let the sharing coroutine finish once a finite
// upstream completes, so an enclosing runBlocking can return.
fun main() = runBlocking {
    println(flowOf(1, 2).shareIn(this, SharingStarted.Eagerly).first())
    val s = flowOf(3, 4).stateIn(this, SharingStarted.Eagerly, 0)
    println(s.first())
    println(flowOf(5, 6).shareIn(this, SharingStarted.Lazily).first())
    val t = flowOf(7, 8).stateIn(this, SharingStarted.Lazily, 0)
    println(t.first())
    println("done")
}
