#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ULongSourceMigrationTests {
    @Test
    func testULongLongConstructorIsSourceBackedAndInternal() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected bundled ULong source to type-check, got: \(errors.map { $0.code + ": " + $0.message })"
            )

            let sema = try #require(ctx.sema)
            let constructorFQName = ["kotlin", "ULong"].map(ctx.interner.intern)
            let constructor = try #require(sema.symbols.lookupAll(fqName: constructorFQName).first { symbolID in
                guard sema.symbols.symbol(symbolID)?.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbolID)
                else {
                    return false
                }
                return signature.parameterTypes == [sema.types.longType]
                    && signature.returnType == sema.types.ulongType
            })

            let symbol = try #require(sema.symbols.symbol(constructor))
            #expect(symbol.visibility == .internal)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(constructor))
            #expect(sema.symbols.externalLinkName(for: constructor) == nil)
            let sourceFileID = try #require(sema.symbols.sourceFileID(for: constructor))
            #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/ULong/Stdlib.kt")
        }
    }
}
#endif
