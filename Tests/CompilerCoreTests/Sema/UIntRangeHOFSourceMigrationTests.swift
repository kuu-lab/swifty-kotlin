#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct UIntRangeHOFSourceMigrationTests {
    private let migratedMembers = [
        "forEach",
        "reduce", "reduceIndexed", "fold", "foldIndexed",
        "find", "findLast",
        "first", "firstOrNull", "last", "lastOrNull",
        "any", "all", "none",
    ]

    @Test
    func migratedMembersAreUIntRangeSourceDefinitions() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            for memberName in migratedMembers {
                let fqName = ["kotlin", "ranges", memberName].map(interner.intern)
                let sourceSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let sourceFileID = sema.symbols.sourceFileID(for: symbolID),
                          let signature = sema.symbols.functionSignature(for: symbolID)
                    else {
                        return false
                    }
                    guard ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/ranges/RangeHOF.kt",
                          signature.receiverType != nil,
                          sema.symbols.externalLinkName(for: symbolID) == nil,
                          let receiverType = signature.receiverType,
                          case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                          let receiverSymbol = sema.symbols.symbol(classType.classSymbol)
                    else {
                        return false
                    }
                    return receiverSymbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("ranges"),
                        interner.intern("UIntRange"),
                    ]
                }

                #expect(sourceSymbols.count == 1, "Expected one source-backed UIntRange.\(memberName), got: \(sourceSymbols)")
            }
        }
    }

    @Test
    func UIntRangeCallsBindToSourceDefinitions() throws {
        let source = """
        fun probe() {
            (1u..5u).forEach { _ -> }
            (1u..5u).reduce { accumulator, value -> accumulator + value }
            (1u..5u).reduceIndexed { index, accumulator, value -> accumulator + index.toUInt() + value }
            (1u..5u).fold(10u) { accumulator, value -> accumulator + value }
            (1u..5u).foldIndexed(10u) { index, accumulator, value -> accumulator + index.toUInt() + value }
            (1u..5u).find { value -> value % 2u == 0u }
            (1u..5u).findLast { value -> value % 2u == 0u }
            (1u..5u).first { value -> value > 1u }
            (1u..5u).firstOrNull { value -> value > 1u }
            (1u..5u).last { value -> value > 1u }
            (1u..5u).lastOrNull { value -> value > 1u }
            (1u..5u).any { value -> value > 1u }
            (1u..5u).all { value -> value > 0u }
            (1u..5u).none { value -> value > 5u }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected UIntRange HOFs to type-check: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expected = Set(migratedMembers)
            var seen = Set<String>()

            for offset in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(offset))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID)
                else { continue }
                let memberName = ctx.interner.resolve(callee)
                guard expected.contains(memberName) else { continue }
                guard let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee
                else {
                    Issue.record("Missing UIntRange call binding for \(memberName)")
                    continue
                }
                #expect(sema.symbols.isSourceBackedSymbol(chosenCallee), "Expected UIntRange.\(memberName) to be source-backed")
                let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                let receiverType = try #require(signature.receiverType)
                let (_, receiverSymbol) = try #require(resolveClassTypeSymbol(receiverType, sema: sema))
                #expect(
                    receiverSymbol.fqName == [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("ranges"),
                        ctx.interner.intern("UIntRange"),
                    ],
                    "Unexpected chosen receiver for UIntRange.\(memberName)"
                )
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                seen.insert(memberName)
            }

            #expect(seen == expected, "Missing source-backed UIntRange calls: \(expected.subtracting(seen))")
        }
    }
}
#endif
