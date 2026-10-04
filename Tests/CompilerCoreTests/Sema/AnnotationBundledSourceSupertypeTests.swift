@testable import CompilerCore
import Foundation
import Testing

/// Regression coverage for KSP-719: the bundled `kotlin.Annotation` source
/// reuses the synthetic `kotlin.Annotation` symbol, but `bindInheritanceEdges`
/// sees an interface with no explicit supertype and would otherwise overwrite
/// the `kotlin.Any` supertype installed by `registerSyntheticAnyStub`.
@Suite
struct AnnotationBundledSourceSupertypeTests {

    @Test
    func testBundledAnnotationKeepsAnyDirectSupertype() throws {
        let source = """
        annotation class Marker
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let annotationSym = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("Annotation"),
        ]))

        let anySym = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("Any"),
        ]))

        let directSupertypes = sema.symbols.directSupertypes(for: annotationSym)
        #expect(
            directSupertypes.contains(anySym),
            "kotlin.Annotation should list kotlin.Any as a direct supertype, got: \(directSupertypes)"
        )

        #expect(
            sema.types.isNominalSubtypeSymbol(annotationSym, of: anySym),
            "kotlin.Annotation should be a nominal subtype of kotlin.Any"
        )
    }

    @Test
    func testAnyMemberCallsOnAnnotationReceiverResolve() throws {
        let source = """
        annotation class Marker

        fun annotationToString(a: Annotation): String = a.toString()
        fun annotationHashCode(a: Annotation): Int = a.hashCode()
        fun annotationEquals(a: Annotation, b: Annotation?): Boolean = a.equals(b)
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            ctx.diagnostics.diagnostics.isEmpty,
            "Expected Any member calls on an Annotation receiver to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
