@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct TopLevelInferredRangeContainsTests {
    @Test(arguments: [false, true])
    func inferredTopLevelRangesResolveContainsAlongsideControls(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let libraryPath = useArtifact ? CompilerOptions.defaultStdlibLibraryPath : nil
        let source = """
        val inferredCharRange = '1'..'3'
        val inferredIntRange = 1..3

        fun topLevelContains(): Boolean =
            inferredCharRange.contains('2') && inferredIntRange.contains(2)

        fun topLevelMembership(): Boolean =
            '2' in inferredCharRange && 2 in inferredIntRange

        fun explicitTypeControls(): Boolean {
            val explicitCharRange: CharRange = CharRange('1', '3')
            val explicitIntRange: IntRange = IntRange(1, 3)
            return explicitCharRange.contains('2') && explicitIntRange.contains(2)
        }

        fun literalControls(): Boolean =
            ('1'..'3').contains('2') && (1..3).contains(2)

        fun localInferenceControls(): Boolean {
            val localCharRange = '1'..'3'
            val localIntRange = 1..3
            return localCharRange.contains('2') && localIntRange.contains(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: !useArtifact,
                stdlibLibraryPath: libraryPath,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            let userErrors = ctx.diagnostics.diagnostics.filter { diagnostic in
                guard diagnostic.severity == .error,
                      let range = diagnostic.primaryRange
                else { return false }
                return ctx.sourceManager.origin(of: range.start.file) == .user
            }
            #expect(userErrors.isEmpty, "Unexpected user source diagnostics: \(userErrors)")

            let expectedTopLevelCallOffsets = Set([
                "inferredCharRange.contains('2')",
                "inferredIntRange.contains(2)"
            ].compactMap { call -> Int? in
                guard let match = source.range(of: call) else { return nil }
                return source[..<match.lowerBound].utf8.count
            })
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            var resolvedTopLevelCalls: Set<Int> = []
            for index in ast.arena.exprs.indices {
                let id = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(id),
                      ctx.sourceManager.origin(of: range.start.file) == .user,
                      let binding = sema.bindings.callBinding(for: id),
                      let symbol = sema.symbols.symbol(binding.chosenCallee),
                      ctx.interner.resolve(symbol.name) == "contains"
                else { continue }
                if expectedTopLevelCallOffsets.contains(range.start.offset) {
                    resolvedTopLevelCalls.insert(range.start.offset)
                }
            }
            #expect(
                resolvedTopLevelCalls == expectedTopLevelCallOffsets,
                "Top-level inferred contains calls should bind: \(resolvedTopLevelCalls)"
            )
        }
    }

    @Test(arguments: [false, true])
    func inferredTopLevelCharRangeStillRejectsAnIntArgument(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let libraryPath = useArtifact ? CompilerOptions.defaultStdlibLibraryPath : nil
        let source = """
        val inferredCharRange = '1'..'3'
        fun wrongArgument(): Boolean = inferredCharRange.contains(2)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: !useArtifact,
                stdlibLibraryPath: libraryPath,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            let userErrors = ctx.diagnostics.diagnostics.filter { diagnostic in
                guard diagnostic.severity == .error,
                      let range = diagnostic.primaryRange
                else { return false }
                return ctx.sourceManager.origin(of: range.start.file) == .user
            }
            #expect(
                userErrors.contains { $0.code == "KSWIFTK-SEMA-0473" },
                "A CharRange must reject an Int contains argument: \(userErrors)"
            )
        }
    }
}
