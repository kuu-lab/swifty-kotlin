@testable import CompilerCore
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct UninitializedLocalValSmartCastTests {
    private func makeContext(_ source: String) throws -> CompilationContext {
        TestStdlibCache.shared.prepare()
        _ = try #require(CompilerOptions.defaultStdlibLibraryPath, "Expected a prepared shared stdlib artifact")
        return makeContextFromSource(source, allowDefaultStdlibLibrary: true)
    }

    @Test func firstAssignmentNarrowsDeclaredValToString() throws {
        let ctx = try makeContext("""
        fun box(): String {
            val value: Any?
            value = "OK"
            return if (value.length == 2) "OK" else "FAIL"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func firstAssignmentNarrowsDeclaredValToBoolean() throws {
        let ctx = try makeContext("""
        fun box(): String {
            val value: Any?
            value = true
            return if (value.compareTo(false) == 1) "OK" else "FAIL"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "if (flag) value = \"one\" else value = \"two\"",
        "when (flag) { true -> value = \"one\"; false -> value = \"two\" }",
        "try { value = \"one\" } catch (error: Exception) { value = \"two\" }"
    ])
    func sameSubtypeAssignedOnEveryCompletingBranchIsJoined(_ assignment: String) throws {
        let ctx = try makeContext("""
        fun read(flag: Boolean): Int {
            val value: Any?
            \(assignment)
            return value.length
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func differentBranchTypesJoinWithoutNarrowingToEitherType() throws {
        let ctx = try makeContext("""
        fun read(flag: Boolean): Int {
            val value: Any?
            if (flag) value = "one" else value = true
            return value.length
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test func initializedDeclaredValKeepsItsDeclaredType() throws {
        let ctx = try makeContext("""
        fun read(): Int {
            val value: Any? = "OK"
            return value.length
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test(arguments: [
        "var value: Any? = \"OK\"; value = true; value.length",
        "var value: Any? = \"OK\"; val overwrite = { value = true }; value.length"
    ])
    func mutableLocalsAreNotNarrowedAcrossWrites(_ body: String) throws {
        let ctx = try makeContext("""
        fun read() {
            \(body)
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test func uninitializedReadIsStillRejected() throws {
        let ctx = try makeContext("""
        fun read() {
            val value: Any?
            value.toString()
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
    }
}
