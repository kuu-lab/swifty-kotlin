#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - Object member call trailing-lambda inference

// Targets: TypeCheck/CallTypeChecker+MemberCallInferenceContext.swift

extension DataFlowAndSemaRegressionTests {
    // DEBT-DIFF-006: a named `object`'s member function taking a lambda
    // parameter (e.g. `(Foo) -> Foo`) failed to infer the lambda's parameter
    // type when called via a trailing lambda literal. Root cause:
    // tryInferFQNPackageTopLevelCall misidentified `SomeObject.member(...)`
    // as a package-qualified top-level call (like `kotlin.math.abs(x)`)
    // whenever a symbol happened to be registered under the same
    // owner-FQName + member-name path, and that fallback infers every
    // argument eagerly with no expected type — leaving the lambda's `it`/
    // named parameters unresolved.
    @Test func testObjectMemberFunctionInfersTrailingLambdaParameterType() throws {
        let source = """
        data class Foo(val x: Int)

        object Registry {
            fun update(block: (Foo) -> Foo): Foo = block(Foo(0))
        }

        fun main() {
            println(Registry.update { m -> m.copy(x = m.x + 1) }.x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.isEmpty, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.code))")
        }
    }

    // Same bug reached with an implicit single-parameter lambda (`it`) and a
    // primitive receiver type, which fails earlier (at `it` itself) than the
    // data-class-copy case above.
    @Test func testObjectMemberFunctionInfersImplicitItParameterType() throws {
        let source = """
        object Registry {
            fun update(block: (Int) -> Int): Int = block(5)
        }

        fun main() {
            println(Registry.update { it + 1 })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.isEmpty, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.code))")
        }
    }

    // A class instance (as opposed to an object singleton) already worked
    // before the fix; kept here as a same-shape control so a future change
    // can't silently regress this case while "fixing" the object case.
    @Test func testClassInstanceMemberFunctionInfersTrailingLambdaParameterType() throws {
        let source = """
        data class Foo(val x: Int)

        class Registry {
            fun update(block: (Foo) -> Foo): Foo = block(Foo(0))
        }

        fun main() {
            println(Registry().update { m -> m.copy(x = m.x + 1) }.x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.isEmpty, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.code))")
        }
    }
}
#endif
