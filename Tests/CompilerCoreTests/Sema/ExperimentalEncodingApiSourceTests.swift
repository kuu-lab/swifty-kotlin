#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ExperimentalEncodingApiSourceTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        let pair = try makeSema()
        Self._sharedSema = pair
        return pair
    }

    private func markerSymbol(
        sema: SemaModule,
        interner: StringInterner
    ) throws -> SymbolID {
        try #require(
            sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("io"),
                interner.intern("encoding"),
                interner.intern("ExperimentalEncodingApi"),
            ]),
            "kotlin.io.encoding.ExperimentalEncodingApi must be registered"
        )
    }

    @Test func testExperimentalEncodingApiCarriesKotlin2310Metadata() throws {
        let (sema, interner) = try sharedSema()
        let symbolID = try markerSymbol(sema: sema, interner: interner)
        let symbol = try #require(sema.symbols.symbol(symbolID))

        #expect(symbol.kind == .annotationClass)
        #expect(symbol.visibility == .public)
        #expect(!symbol.flags.contains(.synthetic))
        #expect(!symbol.flags.contains(.expectDeclaration))
        #expect(!symbol.flags.contains(.actualDeclaration))

        let annotations = sema.symbols.annotations(for: symbolID)
        let requiresOptIn = try #require(
            annotations.first { $0.annotationFQName == "kotlin.RequiresOptIn" },
            "ExperimentalEncodingApi must carry @RequiresOptIn"
        )
        #expect(requiresOptIn.arguments == ["level=RequiresOptIn.Level.ERROR"])

        let target = try #require(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Target" },
            "ExperimentalEncodingApi must carry @Target metadata"
        )
        #expect(target.arguments == [
            "AnnotationTarget.CLASS",
            "AnnotationTarget.ANNOTATION_CLASS",
            "AnnotationTarget.PROPERTY",
            "AnnotationTarget.FIELD",
            "AnnotationTarget.LOCAL_VARIABLE",
            "AnnotationTarget.VALUE_PARAMETER",
            "AnnotationTarget.CONSTRUCTOR",
            "AnnotationTarget.FUNCTION",
            "AnnotationTarget.PROPERTY_GETTER",
            "AnnotationTarget.PROPERTY_SETTER",
            "AnnotationTarget.TYPEALIAS",
        ])

        #expect(annotations.contains {
            $0.annotationFQName == "kotlin.annotation.Retention"
                && $0.arguments == ["AnnotationRetention.BINARY"]
        })
        #expect(annotations.contains { $0.annotationFQName == "kotlin.annotation.MustBeDocumented" })
        #expect(annotations.contains {
            KnownCompilerAnnotation.sinceKotlin.matches($0.annotationFQName)
                && $0.arguments.first?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) == "1.8"
        })
    }

    @Test func testExperimentalEncodingApiIsApplicableToFunctionDeclarations() {
        let ctx = makeContextFromSource("""
        import kotlin.io.encoding.ExperimentalEncodingApi

        @ExperimentalEncodingApi
        fun experimentalEncodingApiSurface(): String = "ok"
        """)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostics are asserted below.
        }

        let targetDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET"
        }
        #expect(
            targetDiagnostics.isEmpty,
            "ExperimentalEncodingApi should be applicable to functions, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
