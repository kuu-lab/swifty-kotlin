#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct DefinitelyNullMemberCallDiagnosticTests {
    @Test(arguments: ["write", "writeX"])
    func reportsNoViableOverloadForDeclaredMemberAfterNullAssignment(callee: String) throws {
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
        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        #expect(
            !ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-0480" || $0.code == "KSWIFTK-SEMA-0024"
            },
            "Expected the declared-member diagnostic, got: \(ctx.diagnostics.diagnostics.map(\.code))"
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
            !ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" },
            "Expected the lookup diagnostic to remain, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }
}
#endif
