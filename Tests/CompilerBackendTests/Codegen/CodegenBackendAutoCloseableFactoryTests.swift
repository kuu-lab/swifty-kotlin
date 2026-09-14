#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendAutoCloseableFactoryTests {

    @Test
    func testCodegenCompilesAutoCloseableFactory() throws {
        let source = """
        fun main() {
            var closed = 0
            val resource: AutoCloseable = AutoCloseable {
                closed = closed + 1
                println("closed:" + closed)
            }
            resource.close()
            println("after-close:" + closed)
            AutoCloseable {
                println("use-close")
            }.use {
                println("use-body")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "AutoCloseableFactory", expected: "closed:1\nafter-close:1\nuse-body\nuse-close\n")
    }

    @Test
    func testCodegenCompilesNullableAutoCloseableUse() throws {
        let source = """
        fun main() {
            var closed = 0
            val missing: AutoCloseable? = null
            val missingResult = missing.use { resource ->
                if (resource == null) "missing" else "bad"
            }
            println(missingResult)
            println("closed:" + closed)

            val present: AutoCloseable? = AutoCloseable {
                closed = closed + 1
                println("closed:" + closed)
            }
            val presentResult = present.use { resource ->
                if (resource == null) "bad" else "present"
            }
            println(presentResult)
            println("after:" + closed)
        }
        """

        try assertKotlinOutput(source, moduleName: "NullableAutoCloseableUse", expected: "missing\nclosed:0\nclosed:1\npresent\nafter:1\n")
    }

    @Test
    func testCodegenPreservesPrimaryAndSuppressedCloseExceptions() throws {
        let source = """
        class ThrowingResource(private val throwOnClose: Boolean) : AutoCloseable {
            override fun close() {
                if (throwOnClose) throw IllegalStateException("close")
            }
        }

        fun main() {
            try {
                ThrowingResource(false).use {
                    throw IllegalStateException("primary-only")
                }
            } catch (e: Throwable) {
                println(e.message)
                println(e.suppressedExceptions.size)
            }

            try {
                ThrowingResource(true).use {
                    throw IllegalStateException("primary")
                }
            } catch (e: Throwable) {
                println(e.message)
                println(e.suppressedExceptions.size)
                println(e.suppressedExceptions[0].message)
            }

            try {
                ThrowingResource(true).use { "body" }
            } catch (e: Throwable) {
                println(e.message)
                println(e.suppressedExceptions.size)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "AutoCloseableCloseFinallyExceptions",
            expected: "primary-only\n0\nprimary\n1\nclose\nclose\n0\n"
        )
    }
}
#endif
