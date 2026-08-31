#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct ExperimentalAtomicApiSourceTests {
    private static nonisolated(unsafe) var shared: (CompilationContext, SemaModule, StringInterner)?

    private func sharedSema() throws -> (CompilationContext, SemaModule, StringInterner) {
        if let shared = Self.shared {
            return shared
        }
        var result: (CompilationContext, SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (ctx, try #require(ctx.sema), ctx.interner)
        }
        let shared = try #require(result)
        Self.shared = shared
        return shared
    }

    @Test
    func testExperimentalAtomicApiHasExactSourceBackedConstructorAndMetadata() throws {
        let (ctx, sema, interner) = try sharedSema()
        let markerFQName = ["kotlin", "concurrent", "atomics", "ExperimentalAtomicApi"].map(interner.intern)
        let marker = try #require(sema.symbols.lookup(fqName: markerFQName))
        let markerInfo = try #require(sema.symbols.symbol(marker))
        #expect(markerInfo.kind == .annotationClass)
        #expect(markerInfo.visibility == .public)
        #expect(!markerInfo.flags.contains(.synthetic))
        #expect(
            sema.symbols.sourceFileID(for: marker) == ctx.sourceManager.fileID(
                forPath: "__bundled_kotlin/concurrent/atomics/ExperimentalAtomicApi.kt"
            )
        )

        let markerType = sema.types.make(.classType(ClassType(
            classSymbol: marker,
            args: [],
            nullability: .nonNull
        )))
        let constructor = try #require(sema.symbols.lookupAll(
            fqName: markerFQName + [interner.intern("<init>")]
        ).first { symbol in
            sema.symbols.symbol(symbol)?.kind == .constructor
        })
        let constructorInfo = try #require(sema.symbols.symbol(constructor))
        let constructorSignature = try #require(sema.symbols.functionSignature(for: constructor))
        #expect(constructorInfo.visibility == .public)
        #expect(!constructorInfo.flags.contains(.synthetic))
        #expect(constructorInfo.declSite != nil)
        #expect(constructorSignature.receiverType == markerType)
        #expect(constructorSignature.parameterTypes.isEmpty)
        #expect(constructorSignature.returnType == markerType)

        let annotations = sema.symbols.annotations(for: marker)
        #expect(annotations.contains {
            $0.annotationFQName == "RequiresOptIn"
                && $0.arguments == ["level=RequiresOptIn.Level.ERROR"]
        })
        #expect(annotations.contains {
            $0.annotationFQName == "Retention"
                && $0.arguments == ["AnnotationRetention.BINARY"]
        })
        #expect(annotations.contains {
            $0.annotationFQName == "Target"
                && $0.arguments == [
                    "CLASS",
                    "ANNOTATION_CLASS",
                    "PROPERTY",
                    "FIELD",
                    "LOCAL_VARIABLE",
                    "VALUE_PARAMETER",
                    "CONSTRUCTOR",
                    "FUNCTION",
                    "PROPERTY_GETTER",
                    "PROPERTY_SETTER",
                    "TYPEALIAS",
                ]
        })
        #expect(annotations.contains {
            $0.annotationFQName == "MustBeDocumented"
        })
        #expect(annotations.contains {
            $0.annotationFQName == "SinceKotlin"
                && $0.arguments.contains(where: { $0.contains("2.1") })
        })
    }
}
#endif
