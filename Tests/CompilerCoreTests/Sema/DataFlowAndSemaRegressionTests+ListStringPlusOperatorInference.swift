#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - List<String> + String plus-operator inference

// Targets: TypeCheck/ExprTypeChecker+BinaryAndFlowInference.swift

extension DataFlowAndSemaRegressionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun main() {
            val items: List<String> = listOf("a", "b")
            val x: List<String> = items + "x"
            println(x)
        }
        """,
        """
        package sample1
        data class Meta(val tags: List<String> = emptyList())

        fun addTag(meta: Meta, tag: String): Meta =
            meta.copy(tags = meta.tags + tag)

        fun main() {
            println(addTag(Meta(), "x").tags)
        }
        """,
        """
        package sample2
        fun main() {
            val greeting: String = "hi" + "there"
            println(greeting)
        }
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: (CompilationContext, [String])?

    private func sharedCtx() throws -> (CompilationContext, [String]) {
        if let cached = Self._sharedCtx { return cached }
        var result: (CompilationContext, [String])?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = (ctx, paths)
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }
    // DEBT-DIFF-006: `someList + "x"` where someList is a List<String> was
    // misinterpreted as string concatenation (`Any.toString() + String`)
    // whenever the RHS happened to be a String, because the string-concat
    // short-circuit (`isString(lhs) || isString(rhs)`) ran before the
    // List/Sequence plus/minus fallback check. This is a plain type-inference
    // bug, independent of data classes, `copy()`, or objects: any
    // `List<String> + String` expression (element type coincides with the
    // RHS's type) was affected. Fixed by reordering the two checks so the
    // collection fallback (which only looks at the LHS's static type) runs
    // first.
    //
    // All three shared sources are checked by this one test:
    // - sample0: the plain `List<String> + String` case above.
    // - sample1: the same bug via a data-class `copy()` named argument with no
    //   intermediate local, matching the exact shape that reaches
    //   `PluginRegistry.update`'s lambda body in
    //   Scripts/diff_cases/compiler_plugin_api.kt (`m.registeredExtensions +
    //   "$kind:$name"`, `m.generatedModules + moduleName`, etc.).
    // - sample2: control — plain `String + String` concatenation must keep
    //   inferring String; the fix only reorders the check relative to
    //   List/Sequence-typed receivers.
    @Test func testListOfStringPlusStringInfersListNotString() throws {
        let (ctx, paths) = try sharedCtx()
        let diagnostics = paths.flatMap { diagnosticsForPath($0, in: ctx) }
        #expect(diagnostics.isEmpty, "Unexpected diagnostics: \(diagnostics.map(\.code))")
    }
}
#endif
