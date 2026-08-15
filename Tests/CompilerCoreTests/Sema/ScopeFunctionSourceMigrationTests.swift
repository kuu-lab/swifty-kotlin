#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ScopeFunctionSourceMigrationTests {
    @Test
    func testRunWithAndApplyAreBundledSourceDeclarations() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Expected scope-function declarations to type-check, got: \(ctx.diagnostics.diagnostics)"
            )

            let sema = try #require(ctx.sema)
            let standardPath = "__bundled_kotlin/Standard.kt"
            let expectedFunctions: [(name: String, minimumCount: Int)] = [
                ("run", 2),
                ("with", 1),
                ("apply", 1),
            ]

            for (name, minimumCount) in expectedFunctions {
                let candidates = sema.symbols.lookupAll(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern(name),
                ])
                let sourceFunctions = candidates.filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          let fileID = sema.symbols.sourceFileID(for: symbolID)
                    else { return false }
                    return !symbol.flags.contains(.synthetic)
                        && sema.symbols.externalLinkName(for: symbolID) == nil
                        && ctx.sourceManager.path(of: fileID) == standardPath
                }

                #expect(
                    sourceFunctions.count >= minimumCount,
                    "Expected bundled source declarations for kotlin.\(name), found \(candidates)"
                )
            }
        }
    }
}
#endif
