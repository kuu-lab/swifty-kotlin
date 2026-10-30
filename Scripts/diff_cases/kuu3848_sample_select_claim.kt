// KUU-3848: a counterparty channel operation can claim a select's parked
// `onReceive`/`onReceiveCatching` offer between the clause's own readiness
// poll and the select's winner dispatch. The externally committed outcome
// lives in the runtime clause (`clause.delivered*`), but the Kotlin clause
// callback still observes the `result` variable captured by its last
// unsuccessful poll — `sample`'s select then misreads the delivered value as
// "channel closed", drops the pending producer, and deadlocks joining the
// still-parked children. The claim window is timing-sensitive, so this case
// loops the ticket's `callbackFlow { send; awaitClose }.sample().take(1)`
// shape: every iteration parks a receive offer that the producer send or the
// producer's close resolves externally.
@file:OptIn(kotlinx.coroutines.FlowPreview::class, kotlinx.coroutines.ExperimentalCoroutinesApi::class, kotlinx.coroutines.InternalCoroutinesApi::class)
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.flow.*

fun main() = runBlocking {
    var emitted = 0
    var cleaned = 0
    repeat(150) {
        callbackFlow<Int> {
            send(3)
            awaitClose { cleaned++ }
        }.sample(1).take(1).collect { value -> if (value == 3) emitted++ }
    }
    println("emitted=$emitted cleaned=$cleaned")
    println("done")
}
