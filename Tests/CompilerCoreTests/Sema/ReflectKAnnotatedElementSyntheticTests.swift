#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKAnnotatedElementSyntheticTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        var context: CompilationContext?
        do {
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try? runSema(ctx)
                context = ctx
            }
        } catch {
            Issue.record(Comment(rawValue: "Failed to run sema: \(error)"))
        }
        return context!
    }

    @Test func testKAnnotatedElementAnnotationsSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let reflectFQ = ["kotlin", "reflect"].map { interner.intern($0) }
        let annotatedElementFQ = reflectFQ + [interner.intern("KAnnotatedElement")]
        let annotatedElementSymbol = try #require(
            sema.symbols.lookup(fqName: annotatedElementFQ),
            "Expected kotlin.reflect.KAnnotatedElement to be registered"
        )
        #expect(sema.symbols.symbol(annotatedElementSymbol)?.kind == .interface)
        #expect(sema.symbols.symbol(annotatedElementSymbol)?.flags.contains(.synthetic) == true)

        let annotationsSymbol = try #require(
            sema.symbols.lookup(fqName: annotatedElementFQ + [interner.intern("annotations")]),
            "Expected KAnnotatedElement.annotations to be registered"
        )
        #expect(sema.symbols.symbol(annotationsSymbol)?.kind == .property)

        let listSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "collections", "List"].map { interner.intern($0) })
        )
        let annotationSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "Annotation"].map { interner.intern($0) })
        )
        let annotationType = sema.types.make(.classType(ClassType(
            classSymbol: annotationSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedAnnotationsType = sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(annotationType)],
            nullability: .nonNull
        )))
        #expect(sema.symbols.propertyType(for: annotationsSymbol) == expectedAnnotationsType)
    }

    @Test func testReflectionInterfacesExposeKAnnotatedElementSupertypes() throws {
        let (sema, interner) = try makeSema()

        let reflectFQ = ["kotlin", "reflect"].map { interner.intern($0) }
        let annotatedElementSymbol = try #require(
            sema.symbols.lookup(fqName: reflectFQ + [interner.intern("KAnnotatedElement")])
        )
        let kCallableSymbol = try #require(
            sema.symbols.lookup(fqName: reflectFQ + [interner.intern("KCallable")])
        )
        let kTypeSymbol = try #require(
            sema.symbols.lookup(fqName: reflectFQ + [interner.intern("KType")])
        )
        let kClassSymbol = try #require(
            sema.symbols.lookup(fqName: reflectFQ + [interner.intern("KClass")])
        )
        let kClassifierSymbol = try #require(
            sema.symbols.lookup(fqName: reflectFQ + [interner.intern("KClassifier")])
        )

        #expect(sema.symbols.directSupertypes(for: kCallableSymbol).contains(annotatedElementSymbol))
        #expect(sema.symbols.directSupertypes(for: kTypeSymbol).contains(annotatedElementSymbol))
        #expect(sema.symbols.directSupertypes(for: kClassSymbol).contains(annotatedElementSymbol))
        #expect(sema.symbols.directSupertypes(for: kClassSymbol).contains(kClassifierSymbol))
        #expect(sema.types.isNominalSubtypeSymbol(kClassSymbol, of: annotatedElementSymbol))
        #expect(sema.types.isNominalSubtypeSymbol(kCallableSymbol, of: annotatedElementSymbol))
    }

    @Test func testKDeclarationContainerMembersSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let reflectFQ = ["kotlin", "reflect"].map { interner.intern($0) }
        let declarationContainerFQ = reflectFQ + [interner.intern("KDeclarationContainer")]
        let declarationContainerSymbol = try #require(
            sema.symbols.lookup(fqName: declarationContainerFQ),
            "Expected kotlin.reflect.KDeclarationContainer to be registered"
        )
        #expect(sema.symbols.symbol(declarationContainerSymbol)?.kind == .interface)
        #expect(sema.symbols.symbol(declarationContainerSymbol)?.flags.contains(.synthetic) == true)

        let membersSymbol = try #require(
            sema.symbols.lookup(fqName: declarationContainerFQ + [interner.intern("members")]),
            "Expected KDeclarationContainer.members to be registered"
        )
        #expect(sema.symbols.symbol(membersSymbol)?.kind == .property)

        let collectionSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "collections", "Collection"].map { interner.intern($0) })
        )
        let kCallableSymbol = try #require(
            sema.symbols.lookup(fqName: reflectFQ + [interner.intern("KCallable")])
        )
        let kCallableStarType = sema.types.make(.classType(ClassType(
            classSymbol: kCallableSymbol,
            args: [.star],
            nullability: .nonNull
        )))
        let expectedMembersType = sema.types.make(.classType(ClassType(
            classSymbol: collectionSymbol,
            args: [.out(kCallableStarType)],
            nullability: .nonNull
        )))
        #expect(sema.symbols.propertyType(for: membersSymbol) == expectedMembersType)

        let kClassSymbol = try #require(
            sema.symbols.lookup(fqName: reflectFQ + [interner.intern("KClass")])
        )
        #expect(sema.symbols.directSupertypes(for: kClassSymbol).contains(declarationContainerSymbol))
        #expect(sema.types.isNominalSubtypeSymbol(kClassSymbol, of: declarationContainerSymbol))
    }

    @Test func testKAnnotatedElementAnnotationsResolveInSource() throws {
        let source = """
        import kotlin.reflect.KAnnotatedElement
        import kotlin.reflect.KDeclarationContainer
        import kotlin.reflect.KClass

        annotation class Marker
        class Box

        fun annotationsOf(element: KAnnotatedElement): Int = element.annotations.size

        fun membersOf(container: KDeclarationContainer): Int = container.members.size

        fun kclassAnnotations(k: KClass<*>): Int = k.annotations.size

        fun classReferenceAsAnnotatedElement(): KAnnotatedElement = Box::class

        fun classReferenceAsDeclarationContainer(): KDeclarationContainer = Box::class
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(
            !(ctx.diagnostics.hasError),
            Comment(rawValue: "Expected KAnnotatedElement.annotations to type-check, got: \(ctx.diagnostics.diagnostics)")
        )
    }
}
#endif
