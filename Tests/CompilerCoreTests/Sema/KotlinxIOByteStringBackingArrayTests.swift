#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct KotlinxIOByteStringBackingArrayTests {
    private func makeContext(_ source: String, useLibrary: Bool) throws -> CompilationContext {
        let library = useLibrary
            ? try #require(CompilerOptions.defaultStdlibLibraryPath, "Fresh stdlib KLIB must be published")
            : nil
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let context = makeCompilationContext(
            inputs: [path],
            stdlibLibraryPath: library,
            allowDefaultStdlibLibrary: false
        )
        _ = context.sourceManager.addFile(path: path, contents: Data(source.utf8))
        #expect(context.options.stdlibLibraryPath == library)
        #expect(context.options.includeStdlib == !useLibrary)
        return context
    }

    private func byteStringGetter(_ context: CompilationContext) throws -> (SemanticSymbol, FunctionSignature) {
        let sema = try #require(context.sema)
        let fqName = "kotlinx.io.bytestring.ByteString.getBackingArrayReference"
        let id = try #require(sema.symbols.lookupAll(fqName: fqName.split(separator: ".").map {
            context.interner.intern(String($0))
        }).first)
        let symbol = try #require(sema.symbols.symbol(id))
        let signature = try #require(sema.symbols.functionSignature(for: id))
        return (symbol, signature)
    }

    @Test(arguments: [false, true])
    func publishedGetterRemainsInternalForNonFriendInlineConsumers(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let context = try makeContext("""
        import kotlinx.io.bytestring.ByteString

        public inline fun publishedBackingArrayProbe(bytes: ByteString): ByteArray =
            bytes.getBackingArrayReference()
        """, useLibrary: useLibrary)
        try? runSema(context)
        #expect(context.diagnostics.diagnostics.contains { $0.severity == .error })

        let (getter, signature) = try byteStringGetter(context)
        #expect(getter.visibility == .internal)
        #expect(getter.flags.contains(.importedLibrary) == useLibrary)
        #expect(signature.receiverType != nil)
        #expect(signature.parameterTypes.isEmpty && signature.valueParameterSymbols.isEmpty)
        #expect(signature.valueParameterHasDefaultValues.isEmpty)
        #expect(signature.valueParameterIsVararg.isEmpty)
        #expect(signature.contextReceiverTypes.isEmpty && signature.contextParameterTypes.isEmpty)
        #expect(signature.typeParameterSymbols.isEmpty)
        #expect(!signature.isSuspend)
        #expect(!signature.canThrow)
        let getterIDs = try #require(context.sema).symbols.lookupAll(fqName: "kotlinx.io.bytestring.ByteString.getBackingArrayReference"
            .split(separator: ".").map { context.interner.intern(String($0)) })
        #expect(getterIDs.count == 1)
        #expect(context.sema?.symbols.annotations(for: getter.id).map(\.annotationFQName) == ["kotlin.PublishedApi"])

        let mangler = NameMangler()
        let sema = try #require(context.sema)
        let resolve: (InternedString) -> String = { context.interner.resolve($0) }
        #expect(mangler.encodeType(
            signature.returnType,
            symbols: sema.symbols,
            types: sema.types,
            nameResolver: resolve,
            unboxValueClasses: false
        ) == "Lkotlin.ByteArray;")
        #expect(mangler.encodeType(
            try #require(signature.receiverType),
            symbols: sema.symbols,
            types: sema.types,
            nameResolver: resolve,
            unboxValueClasses: false
        ) == "Lkotlinx.io.bytestring.ByteString;")
    }

    @Test(arguments: [false, true])
    func suppressedFriendProbeCanCallPublishedGetter(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let context = try makeContext("""
        @file:Suppress("INVISIBLE_MEMBER")

        import kotlinx.io.bytestring.ByteString

        public inline fun publishedBackingArrayProbe(bytes: ByteString): ByteArray =
            bytes.getBackingArrayReference()
        """, useLibrary: useLibrary)
        try runSema(context)
        #expect(!context.diagnostics.hasError, "Suppressed internal friend probe must resolve: \(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func publishedGetterRemainsUnavailableToOrdinaryConsumers(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let context = try makeContext("""
        import kotlinx.io.bytestring.ByteString
        fun ordinaryConsumer(bytes: ByteString): ByteArray = bytes.getBackingArrayReference()
        """, useLibrary: useLibrary)
        try? runSema(context)
        let (getter, _) = try byteStringGetter(context)
        #expect(getter.visibility == .internal)
        #expect(context.diagnostics.diagnostics.contains { $0.severity == .error })
    }
}
#endif
