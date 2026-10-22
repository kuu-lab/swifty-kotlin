#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct NullComparisonSmartCastTests {
    private func makeContextWithoutStdlib(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test func nullSmartCastOriginal() throws {
        let ctx = makeContextFromSource("""
        fun String?.foo() = this ?: "OK"
        fun foo(i: Int?): String {
            if (i == null) return i.foo()
            return "$i"
        }
        fun box() = foo(null)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func nullSmartCastMinimal() throws {
        let ctx = makeContextFromSource("""
        fun String?.foo() = this ?: "OK"
        fun resolveFromNullInt(x: Int?): String {
            if (x == null) return x.foo()
            return "not-null"
        }
        fun box(): String = resolveFromNullInt(null)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func nullSmartCastWhenSubject() throws {
        let ctx = makeContextFromSource("""
        fun String?.foo() = this ?: "OK"
        fun resolveFromNullWhen(x: Int?): String {
            return when (x) {
                null -> x.foo()
                else -> "not-null"
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func nullSmartCastControls() throws {
        let ctx = makeContextFromSource("""
        fun String?.foo() = this ?: "OK"
        fun fromString(x: String?): String {
            if (x == null) return x.foo()
            return "not-null"
        }
        fun fromNothing(x: Nothing?): String {
            if (x == null) return x.foo()
            return "not-null"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func safeCallEqualityWithNonNullValueNarrowsReceiver() throws {
        let ctx = makeContextWithoutStdlib("""
        class N(var color: Int)
        fun test(u: N?) {
            if (u?.color == 1) {
                u.color = 0
                val read = u.color
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func safeCallNullComparisonNarrowsOnlyTheNonNullResultBranch() throws {
        let ctx = makeContextWithoutStdlib("""
        class N(var color: Int)
        fun test(u: N?) {
            if (u?.color != null) {
                u.color = 0
            }
            if (u?.color == null) {
                u.color = 1
            }
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0026" }.count == 1)
    }

    @Test func safeCallEqualityDoesNotNarrowForNullableOrUnequalComparands() throws {
        let ctx = makeContextWithoutStdlib("""
        class N(val color: Int)
        fun test(u: N?, expected: Int?) {
            if (u?.color == expected) {
                u.color
            }
            if (u?.color != 1) {
                u.color
            }
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0026" }.count == 2)
    }

    @Test func notNullBranchDoesNotSmartCastToNothing() throws {
        let ctx = makeContextFromSource("""
        fun String?.foo() = this ?: "OK"
        fun fromInt(x: Int?): String {
            if (x != null) {
                return x.foo()
            }
            return "null"
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains(where: { $0.code == "KSWIFTK-SEMA-0024" }))
    }

    @Test func unstableVarDoesNotSmartCastInNullBranch() throws {
        let ctx = makeContextFromSource("""
        fun String?.foo() = this ?: "OK"
        fun test() {
            var x: Int? = 1
            val mutate = { x = 2 }
            if (x == null) {
                x.foo()
            }
            mutate()
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains(where: { $0.code == "KSWIFTK-SEMA-0024" }))
    }
}
#endif
