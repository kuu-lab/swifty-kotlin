#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ClosureMutationSmartCastTests {
    @Test func narrowsBufferInSuspendFinallyBeforeAppend() throws {
        let ctx = makeContextFromSource("""
        class Buf { fun readString(): String = "" }
        suspend fun f(out: Appendable) {
            var outBuffer: Buf? = null
            fun bufferBytes(count: Long) {
                if (outBuffer == null) { outBuffer = Buf() }
            }
            try { bufferBytes(1) } finally {
                if (outBuffer != null) out.append(outBuffer.readString())
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun fill() { if (buf == null) buf = Buf() }; fill(); if (buf != null) buf.readString()",
        "fun fill() { buf = Buf() }; try { fill() } finally { if (buf != null) buf.readString() }",
        "val fill = { buf = Buf() }; fill(); if (buf != null) buf.readString()",
        "fun fill() { buf = Buf() }; if (buf != null) { fill(); buf.readString() }",
        "fun fill() { buf = Buf() }; fill(); if (buf is Buf) buf.readString()"
    ])
    func narrowsOuterNullableWithNonNullClosureWrites(body: String) throws {
        let ctx = makeNullableCaptureContext("""
        class Buf { fun readString(): String = "ok" }
        suspend fun f() {
            var buf: Buf? = null
            \(body)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "if (buf == null) { buf = Buf() }; buf.write(count)",
        "if (buf == null) buf = Buf(); buf.write(count)",
        "buf = Buf(); buf.write(count)",
        "if (buf != null) buf.write(count)",
        "if (buf == null) { buf = Buf() } else { buf.write(count) }; buf.write(count)",
        "buf = Buf(); when (count) { 1L -> { buf.write(count); buf = null }; else -> buf.write(count) }",
        "buf = Buf(); try { buf.write(count) } finally { buf = null }"
    ])
    func narrowsCapturedNullableWithinMutatingLocalFunction(body: String) throws {
        let ctx = makeNullableCaptureContext("""
        class Buf { fun write(c: Long) {} }
        fun f(src: Int) {
            var buf: Buf? = null
            fun g(count: Long) {
                if (count > 0L) { \(body) }
            }
            g(1L)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun g() { if (buf == null) buf = Buf() }; buf.write(1L)",
        "fun g() { buf = Buf(); buf = null; buf.write(1L) }",
        "fun g(flag: Boolean) { if (flag) buf = Buf(); buf.write(1L) }",
        "fun clear() { buf = null }; fun g() { if (buf == null) buf = Buf(); buf.write(1L) }",
        "fun g() { val clear = { buf = null }; if (buf == null) buf = Buf(); buf.write(1L) }",
        "if (buf != null) { fun g() { buf = null; buf.write(1L) } }",
        "fun g(flag: Boolean) { if (buf != null) { buf = null; if (flag) {}; buf.write(1L) } }",
        "fun g(flag: Boolean) { buf = Buf(); while (flag) { buf = null }; buf.write(1L) }",
        "fun g() { buf = Buf(); for (n in 0..1) { buf = null }; buf.write(1L) }",
        "fun g(flag: Boolean) { buf = Buf(); do { buf = null } while (flag); buf.write(1L) }",
        "fun g(flag: Boolean) { buf = Buf(); when { flag -> buf = null }; buf.write(1L) }",
        "fun g() { buf = Buf(); try { buf = null } finally {}; buf.write(1L) }",
        "fun clear() { buf = null }; if (buf != null) { clear(); buf.write(1L) }",
        "val clear = { buf = null }; if (buf != null) buf.write(1L)",
        "fun maybe(): Buf? = null; fun fill() { buf = maybe() }; if (buf != null) buf.write(1L)",
        "var other: Buf? = null; other = Buf(); val fill = { buf = other }; other = null; if (buf != null) { fill(); buf.write(1L) }",
        "var other: Buf? = null; other = Buf(); val fill = { val snapshot = other; buf = snapshot }; other = null; if (buf != null) { fill(); buf.write(1L) }"
    ])
    func rejectsUnsafeCapturedNullableNarrowing(body: String) throws {
        let ctx = makeNullableCaptureContext("""
        class Buf { fun write(c: Long) {} }
        fun f() {
            var buf: Buf? = null
            \(body)
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0002" || $0.code == "KSWIFTK-SEMA-0022"
        }, "Expected a nullable receiver diagnostic, got: \(ctx.diagnostics.diagnostics.map(\.code))")
    }

    @Test func rejectsNullableCompoundClosureWrite() throws {
        let ctx = makeNullableCaptureContext("""
        operator fun Any?.plus(i: Int): Any? = null
        fun f() {
            var x: Any? = "hi"
            fun clear() { x += 1 }
            if (x != null) { clear(); val y: Any = x }
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Expected the nullable compound write to prevent narrowing")
    }

    private func makeNullableCaptureContext(_ source: String) -> CompilationContext {
        // These regressions use only user declarations and primitive types.
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

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
