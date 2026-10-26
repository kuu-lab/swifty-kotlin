#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct RangeArtifactExactContainsTests {
    @Test(arguments: [false, true])
    func exactPrimitiveContainsResolvesOnBothStdlibSurfaces(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let artifactPath = useArtifact ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let source = """
        fun intRange(range: IntRange, value: Int): Boolean = range.contains(value)
        fun uintRange(range: UIntRange, value: UInt): Boolean = range.contains(value)
        fun ulongRange(range: ULongRange, value: ULong): Boolean = range.contains(value)
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let expectedOwners = Set(["IntRange", "UIntRange", "ULongRange"])
            var resolvedOwners: Set<String> = []

            for index in ast.arena.exprs.indices {
                let id = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(id),
                      ctx.sourceManager.origin(of: range.start.file) == .user,
                      let binding = sema.bindings.callBinding(for: id),
                      let symbol = sema.symbols.symbol(binding.chosenCallee),
                      ctx.interner.resolve(symbol.name) == "contains"
                else { continue }

                let signature = try #require(sema.symbols.functionSignature(for: symbol.id))
                let receiverType = try #require(signature.receiverType)
                guard case let .classType(receiver) = sema.types.kind(of: receiverType),
                      let owner = sema.symbols.symbol(receiver.classSymbol),
                      let ownerName = owner.fqName.map(ctx.interner.resolve).last
                else {
                    Issue.record("Expected a concrete range receiver for contains")
                    continue
                }
                #expect(expectedOwners.contains(ownerName), "Unexpected contains receiver: \(ownerName)")
                #expect(signature.classTypeParameterCount == 0)
                #expect(signature.typeParameterSymbols.isEmpty)
                resolvedOwners.insert(ownerName)
            }

            #expect(resolvedOwners == expectedOwners, "Resolved range owners: \(resolvedOwners)")
        }
    }
}
#endif
