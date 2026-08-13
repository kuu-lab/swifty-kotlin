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
        """
        package sample9
        abstract class EmptyAbstract {
            fun someMethod() {}  // Warning: abstract class has no abstract members
        }
        """,
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.abstractErrorSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }

    @Test func testError_abstractClassInstantiation() throws {
        let ctx = try sharedCtx()
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    @Test func testError_abstractFunctionWithBody() throws {
        let ctx = try sharedCtx()
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    @Test func testError_abstractPropertyWithInitializer() throws {
        let ctx = try sharedCtx()
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    @Test func testError_abstractPrivateMember() throws {
        let ctx = try sharedCtx()
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    @Test func testError_abstractFinalConflict() throws {
        let ctx = try sharedCtx()
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    @Test func testError_sealedFinalConflict() throws {
        let ctx = try sharedCtx()
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    @Test func testError_missingAbstractOverride() throws {
        let ctx = try sharedCtx()
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    @Test func testError_abstractPropertyWithBackingField() throws {
        let ctx = try sharedCtx()
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    @Test func testError_abstractPropertyWithDelegate() throws {
        let ctx = try sharedCtx()
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    @Test func testWarning_emptyAbstractClass() throws {
        let ctx = try sharedCtx()
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-ABSTRACT" && $0.severity == .warning },
            "Expected an ABSTRACT warning for an empty abstract class"
        )
    }
}
#endif
