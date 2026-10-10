import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.channelFlow as aliasedChannelFlow
import kotlinx.coroutines.flow.callbackFlow as aliasedCallbackFlow

fun inferredInts() = channelFlow { send(1); send(2) }
fun inferredStrings() = callbackFlow { trySend("text"); close() }
fun inferredNullable() = channelFlow { send(1); send(null) }
fun inferredMixed() = channelFlow { send(1); send("mixed") }
fun inferredQualified() = channelFlow { this.send(3) }
fun inferredAlias() = aliasedChannelFlow { send(4) }
fun inferredCallbackAlias() = aliasedCallbackFlow(block = { this.trySend("alias"); close() })
fun inferredPackage() = kotlinx.coroutines.flow.channelFlow { send(5) }
fun explicitPackage() = kotlinx.coroutines.flow.callbackFlow<Long> { trySend(13); close() }
fun inferredLatest() = flowOf(1, 2).transformLatest { emit("value:$it") }
fun expectedNumber(): Flow<Number> = channelFlow { send(6) }
fun explicitLong() = channelFlow<Long> { send(7) }
fun <T> genericFlow(value: T): Flow<T> = channelFlow { send(value) }

open class Slot<T> {
    var items: List<T> = emptyList()
    fun put(value: T) { items = items + value }
    fun <U> unrelated(value: U) {}
}
class DerivedSlot<T> : Slot<T>()
class Marker
class MemberSink<T> {
    var items: List<T> = emptyList()
    fun Marker.put(value: T) { items = items + value }
}
fun <T> buildSlot(block: Slot<T>.() -> Unit): Slot<T> {
    val slot = Slot<T>()
    slot.block()
    return slot
}
fun <T> buildDerived(block: DerivedSlot<T>.() -> Unit): DerivedSlot<T> {
    val slot = DerivedSlot<T>()
    slot.block()
    return slot
}
fun inferredSlot() = buildSlot { put("slot") }
fun inferredDerived() = buildDerived { this.put(8) }
fun inferredUnrelatedReceiver(): Slot<Int> {
    val other = Slot<String>()
    val result = buildSlot { other.put("other"); put(9) }
    check(other.items == listOf("other"))
    return result
}
fun <T> buildMember(block: MemberSink<T>.() -> Unit): MemberSink<T> {
    val sink = MemberSink<T>()
    sink.block()
    return sink
}
fun inferredMember() = buildMember { Marker().put("member") }

fun main() = runBlocking {
    val ints: Flow<Int> = inferredInts()
    val strings: Flow<String> = inferredStrings()
    val nullable: Flow<Int?> = inferredNullable()
    val mixed: Flow<Any> = inferredMixed()
    println(ints.toList())
    println(ints.toList())
    println(strings.toList())
    println(nullable.toList())
    println(mixed.toList())
    println(inferredQualified().toList())
    println(inferredAlias().toList())
    println(inferredCallbackAlias().toList())
    println(inferredPackage().toList())
    println(explicitPackage().toList())
    println(inferredLatest().toList())
    println(expectedNumber().toList())
    println(explicitLong().toList())
    println(genericFlow("generic").toList())
    val captured = 10
    var runs = 0
    val cold = channelFlow { send(captured); send(++runs) }
    println(cold.toList())
    println(cold.toList())
    val slot: Slot<String> = inferredSlot()
    val derived: DerivedSlot<Int> = inferredDerived()
    println(slot.items)
    println(derived.items)
    println(inferredUnrelatedReceiver().items)
    val member: MemberSink<String> = inferredMember()
    println(member.items)
}
