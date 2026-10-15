#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct LoweringSuspendTryCatchFinallyTests {
    @Test
    func testSuspendingTryCatchFinallyControlFlow() throws {
        let source = """
        import kotlin.coroutines.*
        import kotlin.coroutines.intrinsics.*

        suspend fun excs() { throw Exception("!!!") }
        suspend fun fff() {}

        class Controller {
            var result = ""
            var count = 0

            suspend fun <T> suspendAndLog(value: T): T = suspendCoroutineUninterceptedOrReturn { continuation ->
                result += "suspend($value);"
                continuation.resume(value)
                COROUTINE_SUSPENDED
            }

            suspend fun suspendLogAndThrow(exception: Throwable): Any? = suspendCoroutineUninterceptedOrReturn { continuation ->
                result += "throw(${exception.message});"
                continuation.resumeWithException(exception)
                COROUTINE_SUSPENDED
            }

            fun expect(expected: Int) {
                if (++count != expected) throw Exception("EXPECTED $expected")
            }

            fun <T> log(value: T) {
                result += "$value"
            }
        }

        fun builder(block: suspend Controller.() -> Unit): String {
            val controller = Controller()
            block.startCoroutine(controller, object : Continuation<Unit> {
                override val context = EmptyCoroutineContext
                override fun resumeWith(result: Result<Unit>) {
                    val exception = result.exceptionOrNull() ?: return
                    controller.result += "caught(${exception.message});"
                }
            })
            return controller.result
        }

        fun builderValue(block: suspend Controller.() -> Int): String {
            val controller = Controller()
            block.startCoroutine(controller, object : Continuation<Int> {
                override val context = EmptyCoroutineContext
                override fun resumeWith(result: Result<Int>) {
                    val exception = result.exceptionOrNull()
                    if (exception == null) {
                        controller.result += "return(${result.getOrThrow()});"
                    } else {
                        controller.result += "throw(${exception.message});"
                    }
                }
            })
            return controller.result
        }

        suspend fun bars(): String {
            var i = 0
            var text = ""
            while (i < 3) {
                ++i
                text += "FAIL$i;"
                try {
                    try {
                        fff()
                        return text
                    } finally {
                        excs()
                    }
                } catch (exception: Exception) {
                    continue
                }
            }
            return "OK"
        }

        suspend fun Controller.makeException(index: Int): Throwable? {
            expect(index)
            return Error("CHECK")
        }

        suspend fun Controller.rethrowException(index: Int, exception: Throwable?) {
            expect(index)
            exception?.let { throw it }
        }

        suspend fun Controller.throwFromFinally() {
            var exception: Throwable? = null
            expect(1)
            try {
                exception = makeException(2)
                log("try(t);")
            } finally {
                rethrowException(3, exception)
                log("FAIL2")
                exception?.let { throw it }
            }
            log("FAIL3")
        }

        fun main() {
            val finallyCatch = builder { result = bars() }
            val throwFromCatch = builder {
                try {
                    try {
                        suspendAndLog("1")
                        suspendLogAndThrow(RuntimeException("exception"))
                    } catch (exception: RuntimeException) {
                        suspendAndLog("caught")
                        suspendLogAndThrow(RuntimeException("fromCatch"))
                    }
                } finally {
                    suspendAndLog("finally")
                }
                suspendAndLog("ignore")
            }
            val throwInTry = builder {
                try {
                    suspendAndLog("before")
                    throw RuntimeException("foo")
                } catch (exception: RuntimeException) {
                    result += "caught(${exception.message});"
                }
                suspendAndLog("after")
            }
            val returnFromFinally = builderValue {
                expect(1)
                log("log(1);")
                try {
                    expect(2)
                    suspendAndLog(2)
                } finally {
                    expect(3)
                    log("log(3);")
                    return@builderValue 4
                }
                log("FAIL")
                -1
            }
            val throwFromFinally = builder {
                try {
                    log("try;")
                    throwFromFinally()
                } catch (exception: Error) {
                    log("catch;")
                }
            }

            println("finallyCatch=$finallyCatch")
            println("throwFromCatch=$throwFromCatch")
            println("throwInTry=$throwInTry")
            println("returnFromFinally=$returnFromFinally")
            println("throwFromFinally=$throwFromFinally")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SuspendTryCatchFinally",
            expected: """
            finallyCatch=OK
            throwFromCatch=suspend(1);throw(exception);suspend(caught);throw(fromCatch);suspend(finally);caught(fromCatch);
            throwInTry=suspend(before);caught(foo);suspend(after);
            returnFromFinally=log(1);suspend(2);log(3);return(4);
            throwFromFinally=try;try(t);catch;
            """ + "\n"
        )
    }
}
#endif
