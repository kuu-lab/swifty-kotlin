#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - List<String> + String plus-operator inference

// Targets: TypeCheck/ExprTypeChecker+BinaryAndFlowInference.swift

extension DataFlowAndSemaRegressionTests {
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
    @Test func testListOfStringPlusStringInfersListNotString() throws {
        let source = """
        fun main() {
            val items: List<String> = listOf("a", "b")
            val x: List<String> = items + "x"
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.isEmpty, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.code))")
        }
    }

    // Same bug via a literal receiver and no intermediate local, matching the
    // exact shape that reaches `PluginRegistry.update`'s lambda body in
    // Scripts/diff_cases/compiler_plugin_api.kt (`m.registeredExtensions +
    // "$kind:$name"`, `m.generatedModules + moduleName`, etc.).
    @Test func testDataClassCopyWithListPlusStringNamedArgument() throws {
        let source = """
        data class Meta(val tags: List<String> = emptyList())

        fun addTag(meta: Meta, tag: String): Meta =
            meta.copy(tags = meta.tags + tag)

        fun main() {
            println(addTag(Meta(), "x").tags)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.isEmpty, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.code))")
        }
    }

    // Control: `Int + String` (never valid in real Kotlin) is unrelated to
    // this fix and must keep behaving exactly as before — the fix only
    // reorders the check relative to List/Sequence-typed receivers, primitive
    // receivers never enter that branch.
    @Test func testStringConcatenationStillInfersStringForNonListReceiver() throws {
        let source = """
        fun main() {
            val greeting: String = "hi" + "there"
            println(greeting)
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
