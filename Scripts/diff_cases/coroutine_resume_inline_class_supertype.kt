// KUU-3673: a suspend value-class result dispatched through an erased
// supertype itable slot must forward COROUTINE_SUSPENDED untouched; the
// bridge used to convert the token into a fake payload, breaking both
// Continuation.resume and thrown-exception delivery.
import kotlin.coroutines.*

interface EntityBase<out ID> {
    suspend fun id(): ID
}

@JvmInline
value class EntityId(val value: String)

interface Entity : EntityBase<EntityId>

var captured: Continuation<EntityId>? = null
var observed = "FAIL"

class SuspendingStub : Entity {
    override suspend fun id(): EntityId = suspendCoroutine { captured = it }
}

class ThrowingStub : Entity {
    override suspend fun id(): EntityId = error("OK")
}

suspend fun test(entity: Entity): EntityId = entity.id()

fun builder(c: suspend () -> Unit) {
    c.startCoroutine(Continuation(EmptyCoroutineContext) {
        it.getOrThrow()
    })
}

fun throwingBuilder(c: suspend () -> Unit) {
    c.startCoroutine(Continuation(EmptyCoroutineContext) {
        observed = it.exceptionOrNull()!!.message!!
    })
}

fun main() {
    builder {
        println(test(SuspendingStub()).value)
    }
    captured?.resume(EntityId("OK"))
    throwingBuilder {
        test(ThrowingStub()).value
    }
    println(observed)
}
