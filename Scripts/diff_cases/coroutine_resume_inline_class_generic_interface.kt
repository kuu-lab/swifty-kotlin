// KUU-2956: a suspend call dispatched through a generic interface bridge must
// relay the callee's completion to the caller continuation so resume() works.
import kotlin.coroutines.*

interface EntityBase<out ID> {
    suspend fun id(): ID
}

@JvmInline
value class EntityId(val value: String)

interface Entity : EntityBase<EntityId>

class EntityStub : Entity {
    var captured: Continuation<EntityId>? = null

    override suspend fun id() = suspendCoroutine<EntityId> { captured = it }
}

private fun builder(c: suspend () -> Unit) {
    c.startCoroutine(object : Continuation<Unit> {
        override val context: CoroutineContext
            get() = EmptyCoroutineContext
        override fun resumeWith(result: Result<Unit>) {
            result.getOrThrow()
        }
    })
}

fun main() {
    val stub = EntityStub()
    val entity: Entity = stub
    builder {
        val id = entity.id()
        println(id.value)
        println("done")
    }
    println("suspended")
    stub.captured!!.resume(EntityId("OK-42"))
    println("resumed")
}
