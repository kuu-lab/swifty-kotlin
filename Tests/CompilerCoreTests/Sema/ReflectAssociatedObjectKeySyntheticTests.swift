#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectAssociatedObjectKeySyntheticTests {
    @Test func testAssociatedObjectKey() throws {
        let sources = [
            """
            package sample0

            annotation class Smoke
            """,
            """
            package sample1

            import kotlin.reflect.AssociatedObjectKey

            @AssociatedObjectKey
            annotation class Binding
            """,
            """
            package sample2

            import kotlin.reflect.AssociatedObjectKey

            @AssociatedObjectKey
            fun notAnAnnotationClass() {}
            """,
        ]

        let ctx = makeContextFromSources(sources)
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted by each test.
        }

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

        let paths = ctx.sourceManager.fileIDs().filter { ctx.sourceManager.origin(of: $0) == .user }
        #expect(paths.count == 3)

        let targetDiagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }
        let sample1Path = paths[1]
        let sample1TargetDiagnostics = targetDiagnostics.filter { $0.primaryRange?.start.file == sample1Path }
        let sample2Path = paths[2]
        let sample2TargetDiagnostics = targetDiagnostics.filter { $0.primaryRange?.start.file == sample2Path }

        #expect(sample1TargetDiagnostics.isEmpty, Comment(rawValue: "Expected annotation-class target to be accepted, got: \(ctx.diagnostics.diagnostics)"))
        #expect(sample2TargetDiagnostics.count == 1, Comment(rawValue: "Expected function target to be rejected, got: \(ctx.diagnostics.diagnostics)"))
    }
}
#endif
