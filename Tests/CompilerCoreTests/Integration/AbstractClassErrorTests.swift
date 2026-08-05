#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite struct AbstractClassErrorTests {
    @Test func testAbstractClassErrors() throws {
        let sources: [String] = [
            // testError_abstractClassInstantiation
            """
            package sample0

                    abstract class Shape {
                        abstract fun area(): Double
                    }
                    fun main() {
                        val s = Shape()  // Error: cannot instantiate abstract class
                    }
            """,
            // testError_abstractFunctionWithBody
            """
            package sample1

                    abstract class Base {
                        abstract fun test() { println("error") }  // Error: abstract function cannot have body
                    }
            """,
            // testError_abstractPropertyWithInitializer
            """
            package sample2

                    abstract class Base {
                        abstract val prop: String = "error"  // Error: abstract property cannot have initializer
                    }
            """,
            // testError_abstractPrivateMember
            """
            package sample3

                    abstract class Base {
                        private abstract fun test()  // Error: abstract member cannot be private
                    }
            """,
            // testError_abstractFinalConflict
            """
            package sample4

                    abstract final class Base  // Error: class cannot be both abstract and final
            """,
            // testError_sealedFinalConflict
            """
            package sample5

                    sealed final class Base  // Error: class cannot be both sealed and final
            """,
            // testError_missingAbstractOverride
            """
            package sample6

                    abstract class Base {
                        abstract fun test()
                    }
                    class Derived : Base() {
                        // Error: must override abstract method
                    }
            """,
            // testError_abstractPropertyWithBackingField
            """
            package sample7

                    abstract class Base {
                        abstract var prop: String
                            field = "error"  // Error: abstract property cannot have explicit backing field
                    }
            """,
            // testError_abstractPropertyWithDelegate
            """
            package sample8

                    abstract class Base {
                        abstract val prop: String by lazy { "error" }  // Error: abstract property cannot have delegate
                    }
            """,
            // testWarning_emptyAbstractClass
            """
            package sample9

                    abstract class EmptyAbstract {
                        fun someMethod() {}  // Warning: abstract class has no abstract members
                    }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            for (index, path) in paths.enumerated() {
                let sampleDiags = diagnosticsForPath(path, in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: sampleDiags)
                if index == 9 {
                    #expect(sampleDiags.first?.severity == .warning)
                }
            }
        }
    }
}
#endif
