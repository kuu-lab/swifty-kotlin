#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Verifies that unsigned `toString(radix)` overloads are bundled Kotlin
/// declarations rather than synthetic runtime-linked members.
@Suite
struct UnsignedStringRadixSourceMigrationTests {
    private static nonisolated(unsafe) var sharedSema: (CompilationContext, SemaModule, StringInterner)?

    private func makeSharedSema() throws -> (CompilationContext, SemaModule, StringInterner) {
        if let shared = Self.sharedSema {
            return shared
        }

        var result: (CompilationContext, SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (ctx, sema, ctx.interner)
        }

        let shared = try #require(result)
        Self.sharedSema = shared
        return shared
    }

    @Test
    func testUnsignedRadixOverloadsAreSourceBacked() throws {
        let (ctx, sema, interner) = try makeSharedSema()
        let fqName = ["kotlin", "text", "toString"].map(interner.intern)
        let sourcePath = "__bundled_kotlin/text/StringNumberConversions.kt"
        let expectedReceivers: [(String, TypeID)] = [
            ("UInt", sema.types.uintType),
            ("ULong", sema.types.ulongType),
            ("UByte", sema.types.ubyteType),
            ("UShort", sema.types.ushortType),
        ]

        let candidates = sema.symbols.lookupAll(fqName: fqName)
        for (typeName, receiverType) in expectedReceivers {
            let symbolID = try #require(
                candidates.first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.receiverType == receiverType
                        && signature.parameterTypes == [sema.types.intType]
                        && signature.returnType == sema.types.stringType
                },
                "Expected \(typeName).toString(radix: Int) in bundled stdlib"
            )
            let symbol = try #require(sema.symbols.symbol(symbolID))

            #expect(symbol.visibility == .public)
            #expect(sema.symbols.isSourceBackedSymbol(symbolID))
            #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
            #expect(
                sema.symbols.sourceFileID(for: symbolID).map { ctx.sourceManager.path(of: $0) } == sourcePath
            )
        }
    }
}
#endif
