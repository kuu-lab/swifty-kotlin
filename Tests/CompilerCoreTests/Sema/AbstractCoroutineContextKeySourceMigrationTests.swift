#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct AbstractCoroutineContextKeySourceMigrationTests {
    @Test(arguments: ["getPolymorphicElement", "minusPolymorphicKey"])
    func polymorphicHelpersHaveOneSourceOwner(name: String) throws {
        let ctx = makeContextFromSource("import kotlin.coroutines.CoroutineContext")
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "coroutines", name].map(ctx.interner.intern)
        let helpers = sema.symbols.lookupAll(fqName: fqName)
        #expect(helpers.count == 1)
        let helper = try #require(helpers.first)
        let info = try #require(sema.symbols.symbol(helper))
        #expect(info.kind == .function)
        #expect(info.visibility == .public)
        #expect(!info.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(helper))
        #expect(sema.symbols.externalLinkName(for: helper) == nil)
        let file = try #require(sema.symbols.sourceFileID(for: helper))
        #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlin/coroutines/CoroutineContextImpl.kt")
        let signature = try #require(sema.symbols.functionSignature(for: helper))
        #expect(signature.receiverType != nil)
        #expect(signature.parameterTypes.count == 1)
        #expect(signature.typeParameterSymbols.count == (name == "getPolymorphicElement" ? 1 : 0))
    }

    @Test(arguments: ["getPolymorphicElement", "minusPolymorphicKey"])
    func polymorphicHelpersRequireOptIn(name: String) throws {
        let source = """
        import kotlin.coroutines.CoroutineContext
        import kotlin.coroutines.\(name)
        fun use(element: CoroutineContext.Element, key: CoroutineContext.Key<CoroutineContext.Element>) {
            element.\(name)(key)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
                && $0.severity == .error
                && $0.message.contains("kotlin.ExperimentalStdlibApi")
        })
    }

    @Test
    func testClassAndConstructorAreBackedByBundledSource() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            let errorSummary = errors.map { "\($0.code): \($0.message)" }.joined(separator: "\n")
            #expect(
                errors.isEmpty,
                "Expected bundled CoroutineContextImpl.kt to type-check, got: \(errorSummary)"
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let classFQName = ["kotlin", "coroutines", "AbstractCoroutineContextKey"].map(interner.intern)
            let classSymbol = try #require(
                sema.symbols.lookupAll(fqName: classFQName).first { symbolID in
                    sema.symbols.symbol(symbolID)?.kind == .class
                }
            )
            let classInfo = try #require(sema.symbols.symbol(classSymbol))

            #expect(!classInfo.flags.contains(.synthetic))
            #expect(sema.types.nominalTypeParameterSymbols(for: classSymbol).count == 2)
            #expect(sema.symbols.sourceFileID(for: classSymbol) != nil)

            let constructorSymbol = try #require(
                sema.symbols.lookupAll(fqName: classFQName + [interner.intern("<init>")]).first { symbolID in
                    sema.symbols.symbol(symbolID)?.kind == .constructor
                }
            )
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            let constructorSignature = try #require(sema.symbols.functionSignature(for: constructorSymbol))

            #expect(!constructorInfo.flags.contains(.synthetic))
            #expect(constructorSignature.parameterTypes.count == 2)
            #expect(constructorSignature.classTypeParameterCount == 2)
            #expect(sema.symbols.externalLinkName(for: constructorSymbol) == nil)
        }
    }
}
#endif
