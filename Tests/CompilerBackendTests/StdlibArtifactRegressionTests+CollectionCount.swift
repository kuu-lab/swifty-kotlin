@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-1926: a Collection receiver must bind Iterable.count rather than
    /// emitting a bare count symbol, through both bundled stdlib routes.
    @Test(arguments: [false, true])
    func testCollectionCountPredicate(useArtifact: Bool) throws {
        try checkCollectionCount(
            caseName: "collection_count_predicate.kt",
            expected: "2\n",
            useArtifact: useArtifact
        )
    }

    @Test(arguments: [false, true])
    func testCollectionCountPredicateVariants(useArtifact: Bool) throws {
        try checkCollectionCount(
            caseName: "collection_count_predicate_variants.kt",
            expected: "3\n2\n2\n3\n3\n1\n0\n2\n2\n2\n2\n2\nnull\n2\n42\n2\n2\n2\n2\n",
            useArtifact: useArtifact
        )
    }

    private func checkCollectionCount(caseName: String, expected: String, useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let source = try diffCaseSource(caseName, file: #filePath)
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionCountPredicate",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            if caseName == "collection_count_predicate.kt" {
                let sema = try #require(ctx.sema)
                let module = try #require(ctx.kir)
                let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
                let countCalls = body.compactMap { instruction -> SymbolID? in
                    guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction else { return nil }
                    let symbolName = symbol.flatMap { sema.symbols.symbol($0)?.name }
                    guard symbolName.map({ ctx.interner.resolve($0) }) == "count"
                        || ctx.interner.resolve(callee) == "count"
                    else { return nil }
                    #expect(symbol != nil, "count must have a resolved callee before lowering")
                    return symbol
                }
                #expect(countCalls.count == 1)
                for symbol in countCalls {
                    #expect(sema.symbols.isSourceBackedSymbol(symbol))
                    let signature = try #require(sema.symbols.functionSignature(for: symbol))
                    let receiverType = try #require(signature.receiverType)
                    guard case let .classType(receiver) = sema.types.kind(of: receiverType) else {
                        Issue.record("count must have a nominal Iterable receiver")
                        continue
                    }
                    let owner = try #require(sema.symbols.symbol(receiver.classSymbol))
                    #expect(owner.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "collections", "Iterable"])
                }
            }
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected)
            #expect(result.stderr.isEmpty)
        }
    }
}
