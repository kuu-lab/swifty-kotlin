#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func tryFinallyExpressionsChainIntoPostfixCalls(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun savePages(): Int = 3

            fun main() {
                var itemsSaved = 0
                val itemsTotal = 3
                try {
                    savePages()
                } finally {
                    if (itemsTotal > 0) {
                        println("paused-check itemsTotal=$itemsTotal")
                    } else {
                        println("paused-check none")
                    }
                }.also { itemsSaved = it }
                println("itemsSaved=$itemsSaved")

                val recovered = try {
                    throw IllegalStateException("boom")
                } catch (e: IllegalStateException) {
                    40
                } finally {
                    println("cleanup")
                }.let { it + 2 }
                println("recovered=$recovered")

                try {
                    println("plain")
                } finally {
                    println("plain-finally")
                }
            }
            """, expected: "paused-check itemsTotal=3\nitemsSaved=3\ncleanup\nrecovered=42\nplain\nplain-finally\n", mode: mode, root: root)
        }
    }
}
#endif
