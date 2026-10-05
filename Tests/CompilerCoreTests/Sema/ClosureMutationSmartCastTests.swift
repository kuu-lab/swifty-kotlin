#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ClosureMutationSmartCastTests {
    @Test(arguments: [
        "val cap = { s = 5 }; if (s is String) println(s.length); println(cap)",
        "val cap = { s = 5 }; when (s) { is String -> println(s.length) }; println(cap)",
        "if (s is String) { val cap = { s = 5 }; println(s.length); println(cap) }",
        "fun change() { s = 5 }; if (s is String) println(s.length)",
        "val cap = { val nested = { s = 5 }; println(nested) }; if (s is String) println(s.length)",
        "run { val cap = { s = 5 }; println(cap) }; if (s is String) println(s.length)",
        "val cap = { run { s = 5 } }; if (s is String) println(s.length); println(cap)"
    ])
    func rejectsTypeNarrowing(body: String) throws {
        let ctx = makeContextFromSource("""
        fun main() {
            var s: Any = "hi"
            \(body)
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test(arguments: [
        "val cap = { println(s) }; if (s is String) println(s.length); println(cap)",
        "s = 5; if (s is String) println(s.length)",
        "run { s = 5 }; if (s is String) println(s.length)",
        "run { s = 5; if (s is String) println(s.length) }",
        "run { run { s = 5 } }; if (s is String) println(s.length)",
        "val cap = { var s: Any = 5; s = 6 }; if (s is String) println(s.length); println(cap)",
        "val cap = { var t: Any = s; t = 5 }; if (s is String) println(s.length); println(cap)",
        "val cap = { var t: Any = 5; t = \"hi\"; if (t is String) println(t.length) }; println(cap)"
    ])
    func preservesStableAndDirectlyAssignedLocals(body: String) throws {
        let ctx = makeContextFromSource("""
        fun main() {
            var s: Any = "hi"
            \(body)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: ["", "inline fun inPlace(block: () -> Unit) { block() }"])
    func distinguishesInlineAndEscapingParameters(definition: String) throws {
        let inlineCall = !definition.isEmpty
        let ctx = makeContextFromSource("""
        \(inlineCall ? definition : "fun retain(block: () -> Unit): () -> Unit = block")
        fun main() {
            var s: Any = "hi"
            \(inlineCall ? "inPlace" : "retain") { s = 5 }
            if (s is String) println(s.length)
        }
        """)
        try runSema(ctx)
        if inlineCall {
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        } else {
            assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        }
    }

    @Test func rejectsNullableNarrowing() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            var s: String? = "hi"
            val cap = { s = null }
            if (s != null) println(s.length)
            println(cap)
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0026", in: ctx)
    }
}
#endif
