#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

/// Regression coverage for KUU-3965: kotlinc rejects '@SubclassOptInRequired'
/// on 'annotation class' declarations, and every 'markerClass' vararg entry is
/// validated — entries 2..n were previously skipped.
@Suite
struct SubclassOptInRequiredApplicabilityTests {
    @Test
    func rejectsSubclassOptInRequiredOnAnnotationClass() throws {
        let ctx = runSemaCollectingDiagnostics("""
        @RequiresOptIn
        annotation class M

        @SubclassOptInRequired(M::class)
        annotation class WrongTarget
        """)
        let errors = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)
        #expect(errors.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(errors.allSatisfy(isError))
        #expect(errors.first?.message == "'@SubclassOptInRequired' is not applicable to 'annotation class'.")
    }

    @Test
    func acceptsSubclassOptInRequiredOnRegularClass() throws {
        let ctx = runSemaCollectingDiagnostics("""
        @RequiresOptIn
        annotation class M

        @SubclassOptInRequired(M::class)
        open class Base
        """)
        #expect(diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx).isEmpty,
                "\(ctx.diagnostics.diagnostics)")
        #expect(diagnostics(withCode: "KSWIFTK-SEMA-SUBCLASS-OPT-IN", in: ctx).isEmpty,
                "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func requiresOptInForEveryMarkerClassEntry() throws {
        let ctx = runSemaCollectingDiagnostics("""
        @RequiresOptIn
        annotation class M

        @RequiresOptIn
        annotation class N

        @SubclassOptInRequired(M::class, N::class)
        open class Base

        class Child : Base()
        """)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-SUBCLASS-OPT-IN", in: ctx)
        #expect(diagnostics.count == 2, "\(ctx.diagnostics.diagnostics)")
        #expect(diagnostics.allSatisfy(isError))
        #expect(diagnostics.contains { $0.message.contains("requires opt-in to 'M'") },
                "\(ctx.diagnostics.diagnostics)")
        #expect(diagnostics.contains { $0.message.contains("requires opt-in to 'N'") },
                "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func satisfiedFirstEntryStillRequiresSecondMarker() throws {
        let ctx = runSemaCollectingDiagnostics("""
        @RequiresOptIn
        annotation class M

        @RequiresOptIn
        annotation class N

        @SubclassOptInRequired(M::class, N::class)
        open class Base

        @OptIn(M::class)
        class Child : Base()
        """)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-SUBCLASS-OPT-IN", in: ctx)
        #expect(diagnostics.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(diagnostics.allSatisfy(isError))
        #expect(diagnostics.first?.message.contains("requires opt-in to 'N'") == true,
                "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func checksMarkerValidityOfEveryEntry() throws {
        let ctx = runSemaCollectingDiagnostics("""
        @RequiresOptIn
        annotation class M

        annotation class NotMarker

        @SubclassOptInRequired(M::class, NotMarker::class)
        open class Base

        @OptIn(M::class)
        class Child : Base()
        """)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-SUBCLASS-OPT-IN", in: ctx)
        #expect(diagnostics.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(diagnostics.allSatisfy(isError))
        #expect(diagnostics.first?.message.contains("markerClass") == true,
                "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func keepsPerMarkerSeverity() throws {
        let ctx = runSemaCollectingDiagnostics("""
        @RequiresOptIn(level = RequiresOptIn.Level.WARNING)
        annotation class M

        @RequiresOptIn(level = RequiresOptIn.Level.ERROR)
        annotation class N

        @SubclassOptInRequired(M::class, N::class)
        open class Base

        class Child : Base()
        """)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-SUBCLASS-OPT-IN", in: ctx)
        #expect(diagnostics.count == 2, "\(ctx.diagnostics.diagnostics)")
        let mDiagnostic = diagnostics.first { $0.message.contains("requires opt-in to 'M'") }
        let nDiagnostic = diagnostics.first { $0.message.contains("requires opt-in to 'N'") }
        #expect(mDiagnostic?.severity == .warning, "\(ctx.diagnostics.diagnostics)")
        #expect(nDiagnostic?.severity == .error, "\(ctx.diagnostics.diagnostics)")
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        TestStdlibCache.shared.prepare()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], allowDefaultStdlibLibrary: true)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        do {
            try runSema(ctx)
        } catch {
            // Each test asserts the expected diagnostics.
        }
        return ctx
    }

    private func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }

    private func isError(_ diagnostic: Diagnostic) -> Bool {
        diagnostic.severity == .error
    }
}
#endif
