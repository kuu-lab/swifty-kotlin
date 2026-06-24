#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// STDLIB-CORO-ABI-001: Tests verifying that AbstractCoroutineContextElement,
// AbstractCoroutineContextKey, and the CoroutineContext.plus operator are
// registered as synthetic sema symbols and that user-defined context elements
// subclassing the abstract base resolve without diagnostics.

@Suite
struct CoroutinesABIStubTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    // ── Registration tests ────────────────────────────────────────────────

    @Test
    func testAbstractCoroutineContextElementIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "AbstractCoroutineContextElement"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.coroutines.AbstractCoroutineContextElement to be registered"
        )
        let info = try #require(sema.symbols.symbol(symbol))
        #expect(info.kind == .class)
        #expect(info.flags.contains(.synthetic))
        #expect(info.flags.contains(.abstractType))
    }

    @Test
    func testAbstractCoroutineContextElementSupertype() throws {
        let (sema, interner) = try makeSema()
        let aceFQName = ["kotlin", "coroutines", "AbstractCoroutineContextElement"].map { interner.intern($0) }
        let aceSymbol = try #require(sema.symbols.lookup(fqName: aceFQName))
        let elementFQName = ["kotlin", "coroutines", "CoroutineContext", "Element"].map { interner.intern($0) }
        let elementSymbol = try #require(sema.symbols.lookup(fqName: elementFQName))
        #expect(
            sema.symbols.directSupertypes(for: aceSymbol).contains(elementSymbol),
            "AbstractCoroutineContextElement must extend CoroutineContext.Element"
        )
    }

    @Test
    func testAbstractCoroutineContextElementPrimaryConstructor() throws {
        let (sema, interner) = try makeSema()
        let aceFQName = ["kotlin", "coroutines", "AbstractCoroutineContextElement"].map { interner.intern($0) }
        let aceSymbol = try #require(sema.symbols.lookup(fqName: aceFQName))
        let ctorFQName = aceFQName + [interner.intern("<init>")]
        let ctorSymbol = try #require(
            sema.symbols.lookup(fqName: ctorFQName),
            "Expected primary constructor for AbstractCoroutineContextElement"
        )
        let sig = try #require(sema.symbols.functionSignature(for: ctorSymbol))
        #expect(sig.parameterTypes.count == 1)
        // Receiver type must be ACE itself
        #expect(sig.receiverType == sema.symbols.propertyType(for: aceSymbol))
        // Single parameter must be Key<*>
        let keyFQName = ["kotlin", "coroutines", "CoroutineContext", "Key"].map { interner.intern($0) }
        let keySymbol = try #require(sema.symbols.lookup(fqName: keyFQName))
        guard case let .classType(paramKind) = sema.types.kind(of: sig.parameterTypes[0]) else {
            Issue.record("Expected ACE ctor parameter to be a class type (Key<*>)"); return
        }
        #expect(paramKind.classSymbol == keySymbol)
        #expect(paramKind.args == [.star])
    }

    @Test
    func testAbstractCoroutineContextKeyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "AbstractCoroutineContextKey"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.coroutines.AbstractCoroutineContextKey to be registered"
        )
        let info = try #require(sema.symbols.symbol(symbol))
        #expect(info.kind == .class)
        #expect(info.flags.contains(.synthetic))
        #expect(info.flags.contains(.abstractType))
    }

    @Test
    func testAbstractCoroutineContextKeyHasTwoTypeParameters() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "AbstractCoroutineContextKey"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let typeParams = sema.types.nominalTypeParameterSymbols(for: symbol)
        #expect(typeParams.count == 2, "AbstractCoroutineContextKey must have two type parameters B and E")
    }

    @Test
    func testAbstractCoroutineContextKeyExtendsKey() throws {
        let (sema, interner) = try makeSema()
        let ackFQName = ["kotlin", "coroutines", "AbstractCoroutineContextKey"].map { interner.intern($0) }
        let ackSymbol = try #require(sema.symbols.lookup(fqName: ackFQName))
        let keyFQName = ["kotlin", "coroutines", "CoroutineContext", "Key"].map { interner.intern($0) }
        let keySymbol = try #require(sema.symbols.lookup(fqName: keyFQName))
        #expect(
            sema.symbols.directSupertypes(for: ackSymbol).contains(keySymbol),
            "AbstractCoroutineContextKey must implement CoroutineContext.Key"
        )
    }

    @Test
    func testCoroutineContextPlusOperatorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "CoroutineContext", "plus"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected CoroutineContext.plus operator to be registered"
        )
        let info = try #require(sema.symbols.symbol(symbol))
        #expect(info.kind == .function)
        #expect(info.flags.contains(.operatorFunction))
        #expect(info.flags.contains(.synthetic))
        let sig = try #require(sema.symbols.functionSignature(for: symbol))
        #expect(sig.parameterTypes.count == 1)
        let contextFQName = ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) }
        let contextSymbol = try #require(sema.symbols.lookup(fqName: contextFQName))
        let contextType = sema.types.make(.classType(ClassType(
            classSymbol: contextSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(sig.parameterTypes[0] == contextType)
        #expect(sig.returnType == contextType)
    }

    @Test
    func testCoroutineContextKeyNestedInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "CoroutineContext", "Key"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected CoroutineContext.Key to be registered"
        )
        #expect(sema.symbols.symbol(symbol)?.kind == .interface)
    }

    @Test
    func testCoroutineContextElementNestedInterfaceExtendsCoroutineContext() throws {
        let (sema, interner) = try makeSema()
        let elementFQName = ["kotlin", "coroutines", "CoroutineContext", "Element"].map { interner.intern($0) }
        let elementSymbol = try #require(sema.symbols.lookup(fqName: elementFQName))
        let contextFQName = ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) }
        let contextSymbol = try #require(sema.symbols.lookup(fqName: contextFQName))
        #expect(
            sema.symbols.directSupertypes(for: elementSymbol).contains(contextSymbol),
            "CoroutineContext.Element must extend CoroutineContext"
        )
    }

    @Test
    func testCoroutineContextGetPolymorphicElementIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "getPolymorphicElement"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.coroutines.getPolymorphicElement to be registered"
        )
        let info = try #require(sema.symbols.symbol(symbol))
        #expect(info.kind == .function)
        #expect(info.flags.contains(.synthetic))
        #expect(sema.symbols.externalLinkName(for: symbol) == "kk_context_get")

        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        let elementSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "coroutines", "CoroutineContext", "Element"].map { interner.intern($0) })
        )
        let keySymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "coroutines", "CoroutineContext", "Key"].map { interner.intern($0) })
        )
        let elementType = sema.types.make(.classType(ClassType(
            classSymbol: elementSymbol,
            args: [],
            nullability: .nonNull
        )))
        let typeParam = try #require(signature.typeParameterSymbols.first)
        let typeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParam,
            nullability: .nonNull
        )))
        let keyType = sema.types.make(.classType(ClassType(
            classSymbol: keySymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        #expect(signature.receiverType == elementType)
        #expect(signature.parameterTypes == [keyType])
        #expect(signature.returnType == sema.types.makeNullable(typeParamType))
        #expect(signature.typeParameterUpperBoundsList == [[elementType]])
        #expect(
            sema.symbols.annotations(for: symbol).contains {
                $0.annotationFQName == KnownCompilerAnnotation.experimentalStdlibApi.qualifiedName
            },
            "getPolymorphicElement should carry ExperimentalStdlibApi"
        )
    }

    @Test
    func testCoroutineContextMinusPolymorphicKeyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "minusPolymorphicKey"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.coroutines.minusPolymorphicKey to be registered"
        )
        let info = try #require(sema.symbols.symbol(symbol))
        #expect(info.kind == .function)
        #expect(info.flags.contains(.synthetic))
        #expect(sema.symbols.externalLinkName(for: symbol) == "kk_context_minusKey")

        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        let elementSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "coroutines", "CoroutineContext", "Element"].map { interner.intern($0) })
        )
        let keySymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "coroutines", "CoroutineContext", "Key"].map { interner.intern($0) })
        )
        let contextSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) })
        )
        let elementType = sema.types.make(.classType(ClassType(
            classSymbol: elementSymbol,
            args: [],
            nullability: .nonNull
        )))
        let keyType = sema.types.make(.classType(ClassType(
            classSymbol: keySymbol,
            args: [.star],
            nullability: .nonNull
        )))
        let contextType = sema.types.make(.classType(ClassType(
            classSymbol: contextSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(signature.receiverType == elementType)
        #expect(signature.parameterTypes == [keyType])
        #expect(signature.returnType == contextType)
        #expect(
            sema.symbols.annotations(for: symbol).contains {
                $0.annotationFQName == KnownCompilerAnnotation.experimentalStdlibApi.qualifiedName
            },
            "minusPolymorphicKey should carry ExperimentalStdlibApi"
        )
    }

    // ── Integration / subclassing pattern tests ──────────────────────────────

    @Test
    func testUserDefinedContextElementSubclassResolvesWithoutDiagnostics() throws {
        let source = """
        import kotlin.coroutines.AbstractCoroutineContextElement
        import kotlin.coroutines.CoroutineContext

        class MyElement(
            val value: String
        ) : AbstractCoroutineContextElement(MyElement) {
            companion object Key : CoroutineContext.Key<MyElement>
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                "Expected no errors for user-defined CoroutineContext.Element: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    @Test
    func testCoroutinePlusOperatorResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.EmptyCoroutineContext
        import kotlinx.coroutines.CoroutineName

        fun probe(): kotlin.coroutines.CoroutineContext {
            return EmptyCoroutineContext + CoroutineName("test")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                "Expected CoroutineContext.plus to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    @Test
    func testGetPolymorphicElementResolvesInSourceWithOptIn() throws {
        let source = """
        import kotlin.ExperimentalStdlibApi
        import kotlin.OptIn
        import kotlin.coroutines.AbstractCoroutineContextElement
        import kotlin.coroutines.CoroutineContext
        import kotlin.coroutines.CoroutineContext.Key
        import kotlin.coroutines.getPolymorphicElement

        class MyElement : AbstractCoroutineContextElement(MyElement) {
            companion object Key : CoroutineContext.Key<MyElement>
        }

        @OptIn(ExperimentalStdlibApi::class)
        fun probe(element: MyElement, key: Key<MyElement>): MyElement? {
            return element.getPolymorphicElement(key)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                "Expected getPolymorphicElement to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    @Test
    func testMinusPolymorphicKeyResolvesInSourceWithOptIn() throws {
        let source = """
        import kotlin.ExperimentalStdlibApi
        import kotlin.OptIn
        import kotlin.coroutines.AbstractCoroutineContextElement
        import kotlin.coroutines.CoroutineContext
        import kotlin.coroutines.CoroutineContext.Key
        import kotlin.coroutines.minusPolymorphicKey

        class MyElement : AbstractCoroutineContextElement(MyElement) {
            companion object Key : CoroutineContext.Key<MyElement>
        }

        @OptIn(ExperimentalStdlibApi::class)
        fun probe(element: MyElement, key: Key<MyElement>): CoroutineContext {
            return element.minusPolymorphicKey(key)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                "Expected minusPolymorphicKey to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }
}
#endif
