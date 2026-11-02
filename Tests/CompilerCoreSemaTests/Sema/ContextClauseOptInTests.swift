#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

// KUU-4094: an annotation written *before* the `context(...)` clause degraded
// the whole declaration into a statement, so `@OptIn(...)` never reached the
// function symbol — and usages inside `contract { }` reported
// KSWIFTK-SEMA-OPT-IN even though the annotation covered them (arrow-core's
// `@OptIn(ExperimentalContracts::class) context(raise: Raise<E>) inline fun`).
@Suite
struct ContextClauseOptInTests {
    private static let raisePrelude = """
    import kotlin.contracts.ExperimentalContracts
    import kotlin.contracts.InvocationKind
    import kotlin.contracts.contract

    interface Raise<in E> { fun raise(e: @UnsafeVariance E): Nothing }
    """

    @Test
    func optInBeforeContextCoversContractBlock() throws {
        let ctx = runSemaCollectingDiagnostics("""
        \(Self.raisePrelude)
        @OptIn(ExperimentalContracts::class)
        context(raise: Raise<E>)
        inline fun <E> withError2(t: () -> E): E {
            contract { callsInPlace(t, InvocationKind.EXACTLY_ONCE) }
            return t()
        }
        """)
        #expect(diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx).isEmpty,
                "\(ctx.diagnostics.diagnostics)")
        #expect(!ctx.diagnostics.diagnostics.contains(where: isError),
                "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func markerBeforeContextCoversContractBlock() throws {
        let ctx = runSemaCollectingDiagnostics("""
        \(Self.raisePrelude)
        @ExperimentalContracts
        context(raise: Raise<E>)
        inline fun <E> marked(t: () -> E): E {
            contract { callsInPlace(t, InvocationKind.EXACTLY_ONCE) }
            return t()
        }
        """)
        #expect(diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx).isEmpty,
                "\(ctx.diagnostics.diagnostics)")
        #expect(!ctx.diagnostics.diagnostics.contains(where: isError),
                "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func optInAfterContextCoversContractBlock() throws {
        let ctx = runSemaCollectingDiagnostics("""
        \(Self.raisePrelude)
        context(raise: Raise<E>)
        @OptIn(ExperimentalContracts::class)
        inline fun <E> contextFirst(t: () -> E): E {
            contract { callsInPlace(t, InvocationKind.EXACTLY_ONCE) }
            return t()
        }
        """)
        #expect(diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx).isEmpty,
                "\(ctx.diagnostics.diagnostics)")
        #expect(!ctx.diagnostics.diagnostics.contains(where: isError),
                "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func classLevelOptInCoversMemberContextContract() throws {
        let ctx = runSemaCollectingDiagnostics("""
        \(Self.raisePrelude)
        @OptIn(ExperimentalContracts::class)
        class Holder<E> {
            context(raise: Raise<E>)
            fun member(t: () -> E): E {
                contract { callsInPlace(t, InvocationKind.EXACTLY_ONCE) }
                return t()
            }
        }
        """)
        #expect(diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx).isEmpty,
                "\(ctx.diagnostics.diagnostics)")
        #expect(!ctx.diagnostics.diagnostics.contains(where: isError),
                "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func contractUsageInsideContextFunctionStillRequiresOptIn() throws {
        let ctx = runSemaCollectingDiagnostics("""
        \(Self.raisePrelude)
        context(raise: Raise<E>)
        fun <E> bare(t: () -> E) {
            contract { callsInPlace(t, InvocationKind.EXACTLY_ONCE) }
            t()
        }
        """)
        let optIns = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)
        #expect(optIns.count == 2, "\(ctx.diagnostics.diagnostics)")
        #expect(optIns.allSatisfy(isError))
    }

    @Test
    func annotationBeforeContextStaysOnTheFunDecl() throws {
        let ctx = runSemaCollectingDiagnostics("""
        interface Raise<in E>
        @OptIn(ExperimentalContracts::class)
        context(raise: Raise<E>) fun sameLine() {}
        """)
        let ast = try #require(ctx.ast)
        let funDecls = ast.files.flatMap(\.topLevelDecls).compactMap { id -> FunDecl? in
            guard case let .funDecl(funDecl) = ast.arena.decl(id) else { return nil }
            return funDecl
        }
        let sameLine = try #require(funDecls.first { ctx.interner.resolve($0.name) == "sameLine" })
        #expect(sameLine.annotations.map(\.name).contains("OptIn"))
        #expect(sameLine.contextReceivers.count == 1)
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
