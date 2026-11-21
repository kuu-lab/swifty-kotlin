#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct DefinitelyNullMemberCallDiagnosticTests {
    @Test(arguments: ["write", "writeX"])
    func reportsUnsafeNullableReceiverForDeclaredMemberAfterNullAssignment(callee: String) throws {
        let ctx = makeContextFromSource("""
        class Buf {
            fun write(c: Long) {}
            fun writeX(c: Long) {}
        }
        fun f() {
            var buf: Buf? = null
            buf = Buf()
            buf = null
            buf.\(callee)(1L)
        }
        """)
        try runSema(ctx)
        let diagnostic = try #require(
            ctx.diagnostics.diagnostics.first { $0.code == "KSWIFTK-SEMA-0026" },
            "Expected KSWIFTK-SEMA-0026, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
        #expect(
            diagnostic.message == "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver."
        )
        #expect(
            !ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-0002" || $0.code == "KSWIFTK-SEMA-0480" || $0.code == "KSWIFTK-SEMA-0024"
            },
            "Expected the nullable-receiver diagnostic, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    @Test func validNullableExtensionStillResolvesAfterNullAssignment() throws {
        let ctx = makeContextFromSource("""
        class Buf {
            fun write(c: Long) {}
        }
        fun Buf?.writeX(c: Long) {}
        fun f() {
            var buf: Buf? = null
            buf = Buf()
            buf = null
            buf.writeX(1L)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test func nullableExtensionMissingArgumentKeepsMissingParameterDiagnostic() throws {
        let ctx = makeContextFromSource("""
        class Buf {
            fun write(c: Long) {}
        }
        fun Buf?.writeY(c: Long, d: Long) {}
        fun f() {
            var buf: Buf? = null
            buf = Buf()
            buf = null
            buf.writeY(1L)
        }
        """)
        try runSema(ctx)
        let diagnostic = try #require(
            ctx.diagnostics.diagnostics.first { $0.code == "KSWIFTK-SEMA-0480" },
            "Expected KSWIFTK-SEMA-0480, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
        #expect(diagnostic.message == "No value passed for parameter 'd'.")
        #expect(
            !ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0026" },
            "Expected the missing-parameter diagnostic to remain, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    @Test func genuineMissingMemberStillReportsUnresolvedMember() throws {
        let ctx = makeContextFromSource("""
        class Buf {
            fun write(c: Long) {}
        }
        fun f() {
            var buf: Buf? = null
            buf = Buf()
            buf = null
            buf.missing(1L)
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        #expect(
            !ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0026" },
            "Expected the lookup diagnostic to remain, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    @Test(arguments: ["write", "writeX"])
    func privateDeclaredMemberStillReportsVisibilityAfterNullAssignment(callee: String) throws {
        let ctx = makeContextFromSource("""
        class Buf {
            private fun write(c: Long) {}
            private fun writeX(c: Long) {}
        }
        fun f() {
            var buf: Buf? = null
            buf = Buf()
            buf = null
            buf.\(callee)(1L)
        }
        """)
        try runSema(ctx)
        let diagnostic = try #require(
            ctx.diagnostics.diagnostics.first { $0.code == "KSWIFTK-SEMA-0040" },
            "Expected KSWIFTK-SEMA-0040, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
        #expect(diagnostic.message == "Cannot access '\(callee)': it is private.")
        #expect(
            !ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-0002" || $0.code == "KSWIFTK-SEMA-0026"
            },
            "Expected the visibility diagnostic, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }
}
#endif
