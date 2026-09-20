#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSynchronizedTests {

    @Test
    func testCodegenCompilesSynchronizedBlocks() throws {
        let source = """
        fun main() {
            val lock = object {}
            var counter = 0
            val result = synchronized(lock) {
                counter += 1
                val nested = synchronized(lock) { counter + 40 }
                nested + 1
            }
            println(result)
            println(counter)
        }
        """

        try assertKotlinOutput(source, moduleName: "SynchronizedBlocks", expected: "42\n1\n")
    }

    @Test
    func testCodegenPropagatesThrowFromSynchronizedBlock() throws {
        let source = """
        fun fail(): Int {
            throw IllegalStateException("boom")
        }

        fun main() {
            val lock = object {}
            try {
                synchronized(lock) { fail() }
                println("unreachable")
            } catch (e: Throwable) {
                println(e.message ?: "missing")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "SynchronizedThrow", expected: "boom\n")
    }

    @Test
    func testCodegenMutexUnlockOnUnlockedMutexIsCatchableIllegalStateException() throws {
        let source = """
        import kotlinx.coroutines.sync.Mutex

        fun main() {
            try {
                Mutex().unlock()
                println("unreachable")
            } catch (e: IllegalStateException) {
                println(e.message ?: "missing")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MutexUnlockIllegalState",
            expected: "This mutex is not locked\n"
        )
    }

    @Test
    func testCodegenSemaphoreReleaseBeyondPermitsIsCatchableIllegalStateException() throws {
        let source = """
        import kotlinx.coroutines.sync.Semaphore

        fun main() {
            try {
                Semaphore(1).release()
                println("unreachable")
            } catch (e: IllegalStateException) {
                println(e.message ?: "missing")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SemaphoreReleaseIllegalState",
            expected: "The number of released permits cannot be greater than 1\n"
        )
    }
}
#endif
