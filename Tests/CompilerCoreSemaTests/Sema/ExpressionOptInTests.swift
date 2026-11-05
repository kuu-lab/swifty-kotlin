#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

// KUU-4172: `@OptIn` attached to an expression must scope to that
// expression's inference subtree — covering calls inside it, including
// `return` values and lambda bodies — without leaking into sibling
// expressions.
@Suite
struct ExpressionOptInTests {
    private static let markerPrelude = """
    @RequiresOptIn(level = RequiresOptIn.Level.ERROR)
    annotation class LocalMarker

    @LocalMarker
    fun restricted(): Int = 1

    fun <T> runIt(block: () -> T): T = block()
    """

    @Test
    func optInOnExpressionCoversCallButNotFollowingSibling() throws {
        let source = """
        \(Self.markerPrelude)

        fun caller() {
            @OptIn(LocalMarker::class)
            restricted()
            restricted()
        }
        """
        let ctx = try semaContext(source)
        let optInDiagnostics = userDiagnostics(in: ctx).filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        #expect(optInDiagnostics.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(optInDiagnostics.allSatisfy { $0.severity == .error }, "\(ctx.diagnostics.diagnostics)")
        // The surviving diagnostic must point at the second, unannotated call.
        let siblingStart = try #require(source.range(of: "restricted()\n}", options: .backwards))
            .lowerBound
        let siblingOffset = source.utf8.distance(from: source.startIndex, to: siblingStart)
        #expect(optInDiagnostics.allSatisfy {
            ($0.primaryRange?.start.offset ?? -1) >= siblingOffset
        }, "Only the unannotated sibling should require opt-in: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func optInOnReturnExpressionCoversMemberCallChain() throws {
        let source = """
        @RequiresOptIn(level = RequiresOptIn.Level.ERROR)
        annotation class LocalMarker

        object Wrap {
            @LocalMarker
            fun wrapUnsafe(x: Int): Int = x
        }

        @LocalMarker
        fun restricted(): Int = 1

        fun caller(): Int {
            @OptIn(LocalMarker::class)
            return Wrap.wrapUnsafe(restricted())
        }
        """
        let ctx = try semaContext(source)
        #expect(userDiagnostics(in: ctx).filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }.isEmpty,
                "\(ctx.diagnostics.diagnostics)")
        #expect(!userDiagnostics(in: ctx).contains(where: { $0.severity == .error }),
                "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func optInOnExpressionReachesLambdaBodyButNotSibling() throws {
        let source = """
        \(Self.markerPrelude)

        fun caller() {
            @OptIn(LocalMarker::class)
            runIt { restricted() }
            restricted()
        }
        """
        let ctx = try semaContext(source)
        let optInDiagnostics = userDiagnostics(in: ctx).filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        #expect(optInDiagnostics.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(optInDiagnostics.allSatisfy { $0.severity == .error }, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func optInOnCallArgumentDoesNotCoverSiblingArgument() throws {
        let source = """
        \(Self.markerPrelude)

        fun caller(): Int {
            return runIt {
                restricted() +
                    @OptIn(LocalMarker::class) restricted() +
                    restricted()
            }
        }
        """
        let ctx = try semaContext(source)
        let optInDiagnostics = userDiagnostics(in: ctx).filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        // Both unannotated `restricted()` calls still require opt-in; only the
        // annotated middle argument is covered.
        #expect(optInDiagnostics.count == 2, "\(ctx.diagnostics.diagnostics)")
        #expect(optInDiagnostics.allSatisfy { $0.severity == .error }, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func optInMarkersDoNotLeakAcrossDifferentMarkers() throws {
        let source = """
        @RequiresOptIn(level = RequiresOptIn.Level.ERROR)
        annotation class MarkerA
        @RequiresOptIn(level = RequiresOptIn.Level.ERROR)
        annotation class MarkerB

        @MarkerA fun a() {}
        @MarkerB fun b() {}

        fun caller() {
            @OptIn(MarkerA::class)
            a()
            b()
        }
        """
        let ctx = try semaContext(source)
        let optInDiagnostics = userDiagnostics(in: ctx).filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        #expect(optInDiagnostics.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(optInDiagnostics.first?.message.contains("MarkerB") == true,
                "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nestedOptInExpressionKeepsOuterMarkers() throws {
        let source = """
        @RequiresOptIn(level = RequiresOptIn.Level.ERROR)
        annotation class MarkerA
        @RequiresOptIn(level = RequiresOptIn.Level.ERROR)
        annotation class MarkerB

        @MarkerA fun a() {}
        @MarkerB fun b() {}

        fun <T> runIt(block: () -> T): T = block()

        fun caller() {
            @OptIn(MarkerA::class)
            runIt {
                @OptIn(MarkerB::class)
                b()
                a()
            }
        }
        """
        let ctx = try semaContext(source)
        #expect(userDiagnostics(in: ctx).filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }.isEmpty,
                "\(ctx.diagnostics.diagnostics)")
        #expect(!userDiagnostics(in: ctx).contains(where: { $0.severity == .error }),
                "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func warningLevelMarkerAnnotatedCallIsSilentAndSiblingWarns() throws {
        let source = """
        @RequiresOptIn(level = RequiresOptIn.Level.WARNING)
        annotation class WarnMarker

        @WarnMarker
        fun warnRestricted() {}

        fun warnCaller() {
            @OptIn(WarnMarker::class)
            warnRestricted()
            warnRestricted()
        }
        """
        let ctx = try semaContext(source)
        let optInDiagnostics = userDiagnostics(in: ctx).filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        #expect(optInDiagnostics.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(optInDiagnostics.allSatisfy { $0.severity == .warning }, "\(ctx.diagnostics.diagnostics)")
    }

    private func semaContext(_ source: String) throws -> CompilationContext {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let context = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = context.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(context)
        return context
    }

    private func userDiagnostics(in context: CompilationContext) -> [Diagnostic] {
        context.diagnostics.diagnostics.filter { diagnostic in
            diagnostic.primaryRange.map {
                context.sourceManager.origin(of: $0.start.file) == .user
            } == true
        }
    }
}
#endif
