#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
@testable import GoldenHarnessSupport
import Foundation
import Testing

/// RF-GOLDEN-006 — public references must describe the Kotlin declaration,
/// not the way the bundled stdlib happens to represent it internally.
@Suite("GoldenHarness.PublicReference")
struct GoldenHarnessPublicReferenceTests {
    private struct Fixture {
        let context: StableRenderContext
        let source: SymbolID
        let alias: SymbolID
        let imported: SymbolID
        let overload: SymbolID
        let user: SymbolID
        let unknown: SymbolID
        let signature: FunctionSignature
    }

    private func makeFixture() -> Fixture {
        let (sema, symbols, types, interner) = makeSemaModule()
        let sourceManager = SourceManager()
        let bundledFile = sourceManager.addFile(
            path: "bundled/Api.kt",
            contents: Data("package kotlin.collections\n".utf8),
            origin: .bundledStdlib
        )
        let userFile = sourceManager.addFile(
            path: "input.kt",
            contents: Data("package kotlin.collections\n".utf8),
            origin: .user
        )
        let packageName = interner.intern("kotlin.collections")
        let packageFQName = [packageName]
        let package = symbols.define(
            kind: .package,
            name: packageName,
            fqName: packageFQName,
            declSite: nil,
            visibility: .public
        )
        let receiverName = interner.intern("List")
        let receiverFQName = packageFQName + [receiverName]
        let receiver = symbols.define(
            kind: .interface,
            name: receiverName,
            fqName: receiverFQName,
            declSite: nil,
            visibility: .public
        )
        symbols.setParentSymbol(package, for: receiver)
        let receiverType = types.make(.classType(ClassType(classSymbol: receiver)))
        let functionName = interner.intern("publicApi")
        let functionFQName = packageFQName + [functionName]
        let valueName = interner.intern("value")
        let valueParameter = symbols.define(
            kind: .valueParameter,
            name: valueName,
            fqName: functionFQName + [valueName],
            declSite: SourceRange(
                start: SourceLocation(file: bundledFile, offset: 0),
                end: SourceLocation(file: bundledFile, offset: 1)
            ),
            visibility: .private
        )
        symbols.setSourceFileID(bundledFile, for: valueParameter)
        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [types.intType],
            returnType: types.stringType,
            isSuspend: true,
            canThrow: true,
            valueParameterSymbols: [valueParameter],
            valueParameterHasDefaultValues: [true],
            valueParameterIsVararg: [true]
        )
        let source = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: SourceRange(
                start: SourceLocation(file: bundledFile, offset: 0),
                end: SourceLocation(file: bundledFile, offset: 1)
            ),
            visibility: .public
        )
        symbols.setSourceFileID(bundledFile, for: source)
        symbols.setParentSymbol(receiver, for: source)
        symbols.setFunctionSignature(signature, for: source)
        symbols.setExternalLinkName("kk_public_api", for: source)

        let alias = symbols.define(
            kind: .function,
            name: functionName,
            fqName: receiverFQName + [functionName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(receiver, for: alias)
        symbols.setFunctionSignature(signature, for: alias)
        symbols.setExternalLinkName("kk_public_api", for: alias)

        let imported = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .importedLibrary]
        )
        symbols.setParentSymbol(receiver, for: imported)
        symbols.setFunctionSignature(signature, for: imported)
        symbols.setExternalLinkName("kk_public_api", for: imported)

        let overload = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: SourceRange(
                start: SourceLocation(file: bundledFile, offset: 2),
                end: SourceLocation(file: bundledFile, offset: 3)
            ),
            visibility: .public
        )
        symbols.setSourceFileID(bundledFile, for: overload)
        symbols.setParentSymbol(receiver, for: overload)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [types.stringType],
                returnType: types.stringType
            ),
            for: overload
        )

        let user = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: SourceRange(
                start: SourceLocation(file: userFile, offset: 0),
                end: SourceLocation(file: userFile, offset: 1)
            ),
            visibility: .public
        )
        symbols.setSourceFileID(userFile, for: user)
        symbols.setParentSymbol(receiver, for: user)
        symbols.setFunctionSignature(signature, for: user)

        let unknownName = interner.intern("mystery")
        let unknown = symbols.define(
            kind: .function,
            name: unknownName,
            fqName: [interner.intern("unknown"), unknownName],
            declSite: nil,
            visibility: .public
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [types.intType], returnType: types.stringType),
            for: unknown
        )

        let ast = ASTModule(declarationCount: 0, tokenCount: 0)
        let context = StableRenderContext(
            sema: sema,
            interner: interner,
            ast: ast,
            sourceManager: sourceManager
        )
        return Fixture(
            context: context,
            source: source,
            alias: alias,
            imported: imported,
            overload: overload,
            user: user,
            unknown: unknown,
            signature: signature
        )
    }

    @Test
    func sourceAliasAndImportedFormsSharePublicReference() {
        let fixture = makeFixture()
        let context = fixture.context
        let sourceKey = context.publicReferenceKey(for: fixture.source)

        #expect(sourceKey == context.publicReferenceKey(for: fixture.alias))
        #expect(sourceKey == context.publicReferenceKey(for: fixture.imported))
        #expect(sourceKey.contains("kotlin.collections.publicApi[kind=fun"))
        #expect(sourceKey.contains("ret=String"))
        #expect(sourceKey.contains("defaults=[1]"))
        #expect(sourceKey.contains("vararg=[1]"))
        #expect(sourceKey.contains("names=[value]"))
        #expect(sourceKey.contains("susp"))
        #expect(!sourceKey.contains("kk_public_api"))
        #expect(context.stableKey(for: fixture.source) != context.stableKey(for: fixture.alias))
    }

    @Test
    func overloadAndUserDeclarationRemainDistinct() {
        let fixture = makeFixture()
        let context = fixture.context

        let sourceKey = context.publicReferenceKey(for: fixture.source)
        let overloadKey = context.publicReferenceKey(for: fixture.overload)
        let userKey = context.publicReferenceKey(for: fixture.user)
        #expect(sourceKey != overloadKey)
        #expect(overloadKey.contains("params=String"))
        #expect(sourceKey != userKey)
        #expect(userKey.contains("origin=fixture"))
        #expect(context.publicReferenceKey(for: fixture.unknown).contains("origin=unknown"))
    }

    @Test
    func publicSignatureAndTypeUseTheSameProjection() {
        let fixture = makeFixture()
        let context = fixture.context

        let signature = context.renderPublicSignature(fixture.signature)
        #expect(signature.contains("recv=kotlin.collections.List"))
        #expect(signature.contains("params=[Int]"))
        #expect(signature.contains("ret=String"))
        #expect(signature.contains("defaults=[1]"))
        #expect(signature.contains("vararg=[1]"))
        #expect(signature.contains("suspend"))

        let receiver = fixture.signature.receiverType!
        #expect(context.renderPublicType(receiver) == "kotlin.collections.List")
    }
}
#endif
