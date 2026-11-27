#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func iterableLastPredicatePreservesInlineAndFailureContracts(mode: EmitMode) throws {
        let source = """
        fun expectNoMatch(values: List<Int>) {
            try {
                values.last { it > 10 }
                println("unexpected")
            } catch (e: NoSuchElementException) {
                println("NoSuchElementException")
            }
        }

        fun main() {
            println(listOf(1, 2, 2, 3, 1).last { it > 1 })
            try {
                println(listOf(1, 2, 2, 3, 1).last { it > 10 })
            } catch (e: NoSuchElementException) {
                println("NoSuchElementException")
            }
            expectNoMatch(emptyList())
            expectNoMatch(listOf(1))
        }
        """
        let expected = "3\nNoSuchElementException\nNoSuchElementException\nNoSuchElementException\n"

        try withWorkspace { root in
            try runRuntimeParity(source, expected: expected, mode: mode, root: root)
        }
    }
}
#endif
