#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct KotlinxIOWrapUnsafeByteArrayTests {
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

    private func wrapUnsafe(_ context: CompilationContext) throws -> (SemanticSymbol, FunctionSignature) {
        let sema = try #require(context.sema)
        let fqName = "kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations.wrapUnsafe"
        let ids = sema.symbols.lookupAll(fqName: fqName.split(separator: ".").map {
            context.interner.intern(String($0))
        })
        #expect(ids.count == 1)
        let id = try #require(ids.first)
        let symbol = try #require(sema.symbols.symbol(id))
        let signature = try #require(sema.symbols.functionSignature(for: id))
        return (symbol, signature)
    }

    @Test(arguments: [false, true])
    func optedInConsumerResolvesExactWrapUnsafeContract(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let context = try makeContext("""
        @file:OptIn(kotlinx.io.bytestring.unsafe.UnsafeByteStringApi::class)

        import kotlinx.io.bytestring.ByteString
        import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations

        fun wrapProbe(array: ByteArray): ByteString = UnsafeByteStringOperations.wrapUnsafe(array)
        """, useLibrary: useLibrary)
        try runSema(context)
        try #require(!context.diagnostics.hasError, "Opted-in wrapUnsafe consumer must resolve: \(context.diagnostics.diagnostics)")

        let (function, signature) = try wrapUnsafe(context)
        let sema = try #require(context.sema)
        let symbols = sema.symbols
        #expect(function.kind == .function && function.visibility == .public)
        #expect(function.flags.contains(.importedLibrary) == useLibrary)
        #expect(signature.receiverType != nil)
        #expect(signature.parameterTypes.count == 1)
        #expect(signature.valueParameterSymbols.compactMap { symbols.symbol($0).map { context.interner.resolve($0.name) } } == ["array"])
        #expect(signature.valueParameterHasDefaultValues == [false])
        #expect(signature.valueParameterIsVararg == [false])
        #expect(signature.contextReceiverTypes.isEmpty && signature.contextParameterTypes.isEmpty)
        #expect(signature.typeParameterSymbols.isEmpty)
        #expect(!signature.isSuspend && !signature.canThrow)

        let ownerID = try #require(symbols.parentSymbol(for: function.id))
        let owner = try #require(symbols.symbol(ownerID))
        #expect(owner.kind == .object && owner.visibility == .public)
        #expect(owner.fqName.map { context.interner.resolve($0) }.joined(separator: ".") ==
            "kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations")
        #expect(symbols.annotations(for: ownerID).contains { $0.annotationFQName == "kotlinx.io.bytestring.unsafe.UnsafeByteStringApi" })
        #expect(symbols.annotations(for: function.id).isEmpty)

        let byteArrayID = try #require(symbols.lookup(fqName: ["kotlin", "ByteArray"].map(context.interner.intern)))
        let byteStringID = try #require(symbols.lookup(fqName: ["kotlinx", "io", "bytestring", "ByteString"].map(context.interner.intern)))
        let expectedArray = sema.types.make(.classType(ClassType(classSymbol: byteArrayID, args: [], nullability: .nonNull)))
        let expectedByteString = sema.types.make(.classType(ClassType(classSymbol: byteStringID, args: [], nullability: .nonNull)))
        let expectedReceiver = sema.types.make(.classType(ClassType(classSymbol: ownerID, args: [], nullability: .nonNull)))
        #expect(signature.parameterTypes == [expectedArray])
        #expect(signature.returnType == expectedByteString)
        #expect(signature.receiverType == expectedReceiver)
    }
}
#endif
