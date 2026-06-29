#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectAssociatedObjectKeySyntheticTests {
    @Test func testAssociatedObjectKeyAnnotationSurfaceIsRegistered() throws {
        let ctx = makeContextFromSource("annotation class Smoke")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "reflect", "AssociatedObjectKey"].map { ctx.interner.intern($0) }
        let symbolID = try #require(sema.symbols.lookup(fqName: fqName))
        let symbol = try #require(sema.symbols.symbol(symbolID))

        #expect(symbol.kind == .annotationClass)
        #expect(symbol.visibility == .public)
        #expect(symbol.flags.contains(.synthetic))

        let annotations = sema.symbols.annotations(for: symbolID)
        #expect(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Target"
                    && $0.arguments == ["AnnotationTarget.ANNOTATION_CLASS"]
            },
            Comment(rawValue: "Expected AssociatedObjectKey to target annotation classes, got: \(annotations)")
        )
        #expect(
            annotations.contains {
                $0.annotationFQName == "kotlin.reflect.ExperimentalAssociatedObjects"
            },
            Comment(rawValue: "Expected AssociatedObjectKey to carry ExperimentalAssociatedObjects, got: \(annotations)")
        )
        #expect(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Retention"
                    && $0.arguments.contains("AnnotationRetention.BINARY")
            },
            Comment(rawValue: "Expected AssociatedObjectKey to carry @Retention(BINARY), got: \(annotations)")
        )
    }

    @Test func testAssociatedObjectKeyCanAnnotateAnnotationClass() {
        let source = """
        import kotlin.reflect.AssociatedObjectKey

        @AssociatedObjectKey
        annotation class Binding
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let targetDiagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(targetDiagnostics.isEmpty, Comment(rawValue: "Expected annotation-class target to be accepted, got: \(ctx.diagnostics.diagnostics)"))
    }

    @Test func testAssociatedObjectKeyRejectsFunctionTarget() {
        let source = """
        import kotlin.reflect.AssociatedObjectKey

        @AssociatedObjectKey
        fun notAnAnnotationClass() {}
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let targetDiagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        #expect(targetDiagnostics.count == 1, Comment(rawValue: "Expected function target to be rejected, got: \(ctx.diagnostics.diagnostics)"))
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted by each test.
        }
        return ctx
    }

    private func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }
}
#endif
