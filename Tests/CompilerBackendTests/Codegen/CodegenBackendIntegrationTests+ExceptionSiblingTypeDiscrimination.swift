@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// Regression coverage for the catch-clause / `is` sibling-exception discrimination
// bug: `catch (e: T)` (and the `is` operator) must only match `T` or one of its real
// subtypes, never an unrelated sibling built-in exception. Before the fix, every
// built-in exception constructed via the shared, type-erased kk_throwable_new /
// kk_throwable_new_with_cause runtime entry points (and kk_op_cast's
// ClassCastException) carried no runtime type identity, so kk_op_is's nominal-type
// fallback treated any non-exact-match as a match.
extension CodegenBackendIntegrationTests {
    func testCatchClauseDoesNotWronglyMatchUnrelatedSiblingException() throws {
        let source = """
        fun main() {
            try {
                try {
                    throw IllegalStateException("unrelated boom")
                } catch (e: NumberFormatException) {
                    println("WRONGLY caught IllegalStateException as NumberFormatException")
                }
            } catch (e: IllegalStateException) {
                println("correctly propagated to outer IllegalStateException catch: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CatchSiblingDiscriminationBasic",
            expected: "correctly propagated to outer IllegalStateException catch: unrelated boom\n"
        )
    }

    func testMultiCatchPicksTheDeclaredTypeNotAnEarlierUnrelatedClause() throws {
        let source = """
        fun main() {
            try {
                throw NoSuchElementException("empty")
            } catch (e: UnsupportedOperationException) {
                println("wrong: caught as UnsupportedOperationException")
            } catch (e: NoSuchElementException) {
                println("correct: caught as NoSuchElementException: ${e.message}")
            } catch (e: Throwable) {
                println("wrong: fell through to Throwable catch-all")
            }

            try {
                throw IndexOutOfBoundsException("index 5")
            } catch (e: IllegalArgumentException) {
                println("wrong: caught as IllegalArgumentException")
            } catch (e: IndexOutOfBoundsException) {
                println("correct: caught as IndexOutOfBoundsException: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CatchSiblingDiscriminationMultiClause",
            expected:
                """
                correct: caught as NoSuchElementException: empty
                correct: caught as IndexOutOfBoundsException: index 5
                """ + "\n"
        )
    }

    func testIsOperatorDoesNotWronglyMatchUnrelatedSiblingException() throws {
        let source = """
        fun main() {
            val e: Throwable = IllegalStateException("x")
            println(e is NumberFormatException)
            println(e is IllegalStateException)
            println(e is RuntimeException)
            println(e is Exception)
            println(e is Throwable)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IsOperatorSiblingDiscrimination",
            expected:
                """
                false
                true
                true
                true
                true
                """ + "\n"
        )
    }

    func testFailedReferenceCastThrowsClassCastExceptionNotAnUnrelatedSibling() throws {
        let source = """
        open class Animal
        class Dog : Animal()
        class Cat : Animal()

        fun main() {
            val animal: Animal = Dog()
            try {
                val cat = animal as Cat
                println("wrong: cast succeeded: ${cat}")
            } catch (e: NumberFormatException) {
                println("wrong: ClassCastException wrongly caught as NumberFormatException")
            } catch (e: ClassCastException) {
                println("correct: caught as ClassCastException")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ClassCastSiblingDiscrimination",
            expected: "correct: caught as ClassCastException\n"
        )
    }
}
