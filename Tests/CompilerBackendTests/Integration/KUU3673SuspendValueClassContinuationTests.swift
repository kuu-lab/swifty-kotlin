@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KUU3673SuspendValueClassContinuationTests {
    @Test
    func resumeBoxesValueClassFromSupertypeTypeParameter() throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            """
            import kotlin.coroutines.*

            @JvmInline
            value class EntityId(val value: String)

            interface EntityBase<out ID> {
                suspend fun id(): ID
            }

            interface Entity : EntityBase<EntityId>

            private var continuation: Continuation<EntityId>? = null

            class EntityStub : Entity {
                override suspend fun id(): EntityId = suspendCoroutine { continuation = it }
            }

            suspend fun test(): EntityId {
                val entity: Entity = EntityStub()
                return entity.id()
            }

            private fun builder(block: suspend () -> Unit) {
                block.startCoroutine(Continuation(EmptyCoroutineContext) { it.getOrThrow() })
            }

            fun main() {
                var result = "FAIL"
                builder { result = test().value }
                continuation?.resume(EntityId("OK"))
                println(result)
            }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3673ResumeValueClassFromSupertype",
            allowDefaultStdlibLibrary: true
        )
    }

    @Test
    func resumeWithExceptionPropagatesForValueClassFromSupertype() throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            """
            import kotlin.coroutines.*

            @JvmInline
            value class EntityId(val value: String)

            interface EntityBase<out ID> {
                suspend fun id(): ID
            }

            interface Entity : EntityBase<EntityId>

            private var result = "FAIL"

            class EntityStub : Entity {
                override suspend fun id(): EntityId = error("OK")
            }

            suspend fun test(): EntityId {
                val entity: Entity = EntityStub()
                return entity.id()
            }

            private fun builder(block: suspend () -> Unit) {
                block.startCoroutine(Continuation(EmptyCoroutineContext) {
                    result = it.exceptionOrNull()!!.message!!
                })
            }

            fun main() {
                builder { test().value }
                println(result)
            }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3673ResumeWithExceptionValueClassFromSupertype",
            allowDefaultStdlibLibrary: true
        )
    }
}
