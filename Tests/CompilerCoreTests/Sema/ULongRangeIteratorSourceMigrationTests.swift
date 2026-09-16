#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ULongRangeIteratorSourceMigrationTests {
    private struct ExpectedMember {
        let owner: String
        let name: String
        let parameterCount: Int
        let sourceFile: String
        let expectedCount: Int
    }

    private let migratedMembers = [
        ExpectedMember(owner: "ULongRange", name: "iterator", parameterCount: 0, sourceFile: "RangeIterators.kt", expectedCount: 1),
        ExpectedMember(owner: "ULongProgression", name: "iterator", parameterCount: 0, sourceFile: "RangeIterators.kt", expectedCount: 1),
        // `step` has both Int and Long overloads per owner.
        ExpectedMember(owner: "ULongRange", name: "step", parameterCount: 1, sourceFile: "ProgressionConstructors.kt", expectedCount: 2),
        ExpectedMember(owner: "ULongProgression", name: "step", parameterCount: 1, sourceFile: "ProgressionConstructors.kt", expectedCount: 2),
        ExpectedMember(owner: "ULongRange", name: "take", parameterCount: 1, sourceFile: "RangeHOF.kt", expectedCount: 1),
        ExpectedMember(owner: "ULongRange", name: "drop", parameterCount: 1, sourceFile: "RangeHOF.kt", expectedCount: 1),
        ExpectedMember(owner: "ULongRange", name: "chunked", parameterCount: 1, sourceFile: "RangeHOF.kt", expectedCount: 1),
        ExpectedMember(owner: "ULongRange", name: "windowed", parameterCount: 3, sourceFile: "RangeHOF.kt", expectedCount: 1),
        ExpectedMember(owner: "ULongProgression", name: "take", parameterCount: 1, sourceFile: "RangeHOF.kt", expectedCount: 1),
        ExpectedMember(owner: "ULongProgression", name: "drop", parameterCount: 1, sourceFile: "RangeHOF.kt", expectedCount: 1),
        ExpectedMember(owner: "ULongProgression", name: "chunked", parameterCount: 1, sourceFile: "RangeHOF.kt", expectedCount: 1),
        ExpectedMember(owner: "ULongProgression", name: "windowed", parameterCount: 3, sourceFile: "RangeHOF.kt", expectedCount: 1),
    ]

    @Test
    func migratedMembersAreULongSourceDefinitions() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            for expected in migratedMembers {
                let fqName = ["kotlin", "ranges", expected.name].map(interner.intern)
                let sourceSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          sema.symbols.isSourceBackedSymbol(symbolID),
                          sema.symbols.externalLinkName(for: symbolID) == nil,
                          let sourceFileID = sema.symbols.sourceFileID(for: symbolID),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.parameterTypes.count == expected.parameterCount,
                          let receiverType = signature.receiverType,
                          case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                          let receiverSymbol = sema.symbols.symbol(classType.classSymbol)
                    else {
                        return false
                    }
                    guard ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/ranges/\(expected.sourceFile)"
                    else {
                        return false
                    }
                    return interner.resolve(receiverSymbol.name) == expected.owner
                }

                #expect(
                    sourceSymbols.count == expected.expectedCount,
                    "Expected \(expected.expectedCount) source-backed \(expected.owner).\(expected.name), got: \(sourceSymbols)"
                )
            }
        }
    }

    @Test
    func ULongRangeCallsBindToSourceDefinitions() throws {
        let source = """
        fun rangeToValue(): ULongRange = 1uL.rangeTo(5uL)
        fun rangeOperatorValue(): ULongRange = 1uL..5uL
        fun downToValue(): ULongProgression = 10uL downTo 1uL
        fun rangeStep(range: ULongRange): ULongProgression = range.step(2)
        fun progressionStep(progression: ULongProgression): ULongProgression = progression.step(2)
        fun rangeIterator(range: ULongRange): Iterator<ULong> = range.iterator()
        fun progressionIterator(progression: ULongProgression): Iterator<ULong> = progression.iterator()
        fun rangeTake(range: ULongRange): List<ULong> = range.take(2)
        fun rangeDrop(range: ULongRange): List<ULong> = range.drop(2)
        fun rangeChunked(range: ULongRange): List<List<ULong>> = range.chunked(2)
        fun rangeWindowed(range: ULongRange): List<List<ULong>> = range.windowed(2)
        fun progressionTake(progression: ULongProgression): List<ULong> = progression.take(2)
        fun progressionDrop(progression: ULongProgression): List<ULong> = progression.drop(2)
        fun progressionChunked(progression: ULongProgression): List<List<ULong>> = progression.chunked(2)
        fun progressionWindowed(progression: ULongProgression): List<List<ULong>> = progression.windowed(2, 2, true)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected ULong range migration calls to type-check: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedNames = Set(["rangeTo", "step", "iterator", "take", "drop", "chunked", "windowed"])
            var seen = Set<String>()
            var rangeOperatorSeen = false
            var downToOperatorSeen = false

            for offset in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(offset))
                guard let exprRange = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: exprRange.start.file) == path
                else {
                    continue
                }
                if case let .binary(op, _, _, _) = ast.arena.expr(exprID), op == .rangeTo || op == .downTo {
                    let chosenCallee = try #require(sema.bindings.callBinding(for: exprID)?.chosenCallee)
                    #expect(sema.symbols.isSourceBackedSymbol(chosenCallee), "Expected ULong \(op) operator to be source-backed")
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                    if op == .rangeTo {
                        rangeOperatorSeen = true
                    } else {
                        downToOperatorSeen = true
                    }
                    continue
                }
                guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID) else {
                    continue
                }
                let memberName = ctx.interner.resolve(callee)
                guard expectedNames.contains(memberName) else { continue }
                let chosenCallee = try #require(sema.bindings.callBinding(for: exprID)?.chosenCallee)
                #expect(sema.symbols.isSourceBackedSymbol(chosenCallee), "Expected ULongRange/ULongProgression.\(memberName) to be source-backed")
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                seen.insert(memberName)
            }

            #expect(seen == expectedNames, "Missing source-backed ULong migration calls: \(expectedNames.subtracting(seen))")
            #expect(rangeOperatorSeen, "Missing source-backed ULong rangeTo operator")
            #expect(downToOperatorSeen, "Missing source-backed ULong downTo operator")
        }
    }
}
#endif
