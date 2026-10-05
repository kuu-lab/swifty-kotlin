#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite struct AbstractClassErrorTests {

    private static let abstractErrorSources: [String] = [
        """
        package sample0
        abstract class Shape {
            abstract fun area(): Double
        }
        fun main() {
            val s = Shape()  // Error: cannot instantiate abstract class
        }
        """,
        """
        package sample1
        abstract class Base {
            abstract fun test() { println("error") }  // Error: abstract function cannot have body
        }
        """,
        """
        package sample2
        abstract class Base {
            abstract val prop: String = "error"  // Error: abstract property cannot have initializer
        }
        """,
        """
        package sample3
        abstract class Base {
            private abstract fun test()  // Error: abstract member cannot be private
        }
        """,
        """
        package sample4
        abstract final class Base  // Error: class cannot be both abstract and final
        """,
        """
        package sample5
        sealed final class Base  // Error: class cannot be both sealed and final
        """,
        """
        package sample6
        abstract class Base {
            abstract fun test()
        }
        class Derived : Base() {
            // Error: must override abstract method
        }
        """,
        """
        package sample7
        abstract class Base {
            abstract var prop: String
                field = "error"  // Error: abstract property cannot have explicit backing field
        }
        """,
        """
        package sample8
        abstract class Base {
            abstract val prop: String by lazy { "error" }  // Error: abstract property cannot have delegate
        }
        """,
    ]

    private static let _sharedCtx = Result {
        try semaContext(for: abstractErrorSources)
    }

    @Test func testInvalidAbstractDeclarationsStillError() throws {
        let ctx = try Self._sharedCtx.get()

        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test(arguments: [
        """
        expect abstract class CharsetEncoder
        actual abstract class CharsetEncoder
        abstract class PlainAbstract
        """,
        """
        abstract class ConcreteMembers {
            val value: Int = 1
            fun someMethod() {}
        }
        class Derived : ConcreteMembers()
        """,
        """
        abstract class AbstractOuter {
            abstract class NestedAbstract
        }
        class ConcreteOuter {
            abstract class NestedAbstract
        }
        """,
        """
        abstract class Base {
            abstract fun value(): Int
        }
        abstract class Implemented : Base() {
            override fun value(): Int = 1
        }
        class Derived : Implemented()
        """,
    ])
    func testAbstractClassWithoutAbstractMembersDoesNotWarn(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.isEmpty)
    }

    @Test func testEmptyAbstractClassCannotBeInstantiated() throws {
        let ctx = makeContextFromSource("""
        abstract class PlainAbstract
        fun main() {
            val instance = PlainAbstract()
        }
        """)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-ABSTRACT" && $0.severity == .error }
        )
    }

    @Test func testSealedTypesWithoutAbstractMembers() throws {
        let sources = [
            """
            package sealedEmpty
            sealed class S
            class SA(val x: Int) : S()
            fun main() { println("ok") }
            """,
            """
            package sealedConcrete
            sealed class S {
                val value: Int = 42
                fun answer(): Int = value
            }
            class SA : S()
            """,
            """
            package sealedInterface
            sealed interface S
            class SA : S
            """,
            """
            package sealedNested
            abstract class Outer {
                abstract fun required(): Int
                sealed class Inner
                class Derived : Inner()
            }
            """,
            """
            package sealedOuter
            sealed class Outer {
                abstract class Inner
            }
            """,
            """
            package sealedContract
            sealed class S {
                abstract fun required(): Int
            }
            class SA : S()
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            for path in paths.prefix(4) {
                let diagnostics = diagnosticsForPath(path, in: ctx)
                #expect(!diagnostics.hasError)
                assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: diagnostics)
            }

            let nestedDiagnostics = diagnosticsForPath(paths[4], in: ctx)
            #expect(!nestedDiagnostics.hasError)
            let warnings = nestedDiagnostics.filter {
                $0.code == "KSWIFTK-SEMA-ABSTRACT" && $0.severity == .warning
            }
            #expect(warnings.count == 1)
            #expect(warnings.first?.message == "Abstract class 'sealedOuter.Outer.Inner' has no abstract members. Consider removing the 'abstract' modifier.")

            let contractDiagnostics = diagnosticsForPath(paths[5], in: ctx)
            #expect(contractDiagnostics.hasError)
            #expect(contractDiagnostics.contains {
                $0.code == "KSWIFTK-SEMA-ABSTRACT" && $0.severity == .error
            })
            #expect(!contractDiagnostics.contains { $0.severity == .warning })
        }
    }
}
#endif
