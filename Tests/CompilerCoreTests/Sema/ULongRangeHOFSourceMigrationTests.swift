#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ULongRangeHOFSourceMigrationTests {
    private let migratedMembers = [
        "forEach",
        "reduce", "reduceIndexed", "fold", "foldIndexed",
        "find", "findLast",
        "first", "firstOrNull", "last", "lastOrNull",
        "any", "all", "none",
    ]

    @Test
    func valueSemanticsAreDeclaredOnULongRangeInBundledSource() throws {
        let source = """
        import kotlin.ranges.ULongRange
        fun probe(range: ULongRange) {
            range.endInclusive
            range.endExclusive
            range.isEmpty()
            range.equals(ULongRange(1uL, 3uL))
            range.hashCode()
            range.toString()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "ULongRange value members should type-check: \(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let owner = ["kotlin", "ranges", "ULongRange"].map(ctx.interner.intern)
            let sourcePath = "__bundled_kotlin/ranges/ULongRange/Stdlib.kt"

            for name in ["endInclusive", "endExclusive"] {
                let symbols = sema.symbols.lookupAll(fqName: owner + [ctx.interner.intern(name)]).filter { id in
                    guard let symbol = sema.symbols.symbol(id),
                          symbol.kind == .property,
                          sema.symbols.isSourceBackedSymbol(id),
                          let fileID = sema.symbols.sourceFileID(for: id)
                    else { return false }
                    return ctx.sourceManager.path(of: fileID) == sourcePath
                }
                #expect(symbols.count == 1, "Expected source-backed ULongRange.\(name)")
            }

            for name in ["equals", "hashCode", "isEmpty", "toString"] {
                let symbols = sema.symbols.lookupAll(fqName: owner + [ctx.interner.intern(name)]).filter { id in
                    guard let symbol = sema.symbols.symbol(id),
                          symbol.kind == .function,
                          sema.symbols.isSourceBackedSymbol(id),
                          let fileID = sema.symbols.sourceFileID(for: id)
                    else { return false }
                    return ctx.sourceManager.path(of: fileID) == sourcePath
                }
                #expect(symbols.count == 1, "Expected source-backed ULongRange.\(name)")
            }
        }
    }

    @Test
    func migratedMembersAreULongRangeSourceDefinitions() throws {
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
                    if memberName == "firstOrNull" || memberName == "lastOrNull" {
                        return signature.parameterTypes.count == 1 && receiverSymbol.fqName == [
                            interner.intern("kotlin"),
                            interner.intern("ranges"),
                            interner.intern("ULongRange"),
                        ]
                    }
                    return receiverSymbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("ranges"),
                        interner.intern("ULongRange"),
                    ]
                }

                #expect(sourceSymbols.count == 1, "Expected one source-backed ULongRange.\(memberName), got: \(sourceSymbols)")
            }
        }
    }

    @Test
    func ULongRangeMembershipAndAggregateMembersAreSourceBacked() throws {
        let source = """
        fun probe() {
            (1uL..5uL).contains(3uL)
            (1uL..5uL).isEmpty()
            (1uL..5uL).firstOrNull()
            (1uL..5uL).lastOrNull()
            (1uL..5uL).count()
            (1uL..5uL).sum()
            (1uL..5uL).reversed()
            (1uL..5uL).sorted()
            (1uL..5uL).toList()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected ULongRange source members to type-check: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let containsSymbols = sema.symbols.lookupAll(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("ranges"),
                ctx.interner.intern("contains"),
            ]).filter { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      signature.parameterTypes == [sema.types.ulongType],
                      let receiverType = signature.receiverType,
                      let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema)
                else { return false }
                return receiverSymbol.fqName == [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("ranges"),
                    ctx.interner.intern("ULongRange"),
                ]
            }
            #expect(containsSymbols.count == 1, "Expected one ULongRange.contains(ULong) source declaration, got \(containsSymbols.count)")
            let isEmptySymbols = sema.symbols.lookupAll(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("ranges"),
                ctx.interner.intern("ULongRange"),
                ctx.interner.intern("isEmpty"),
            ]).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(symbolID),
                      let sourceFileID = sema.symbols.sourceFileID(for: symbolID),
                      ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/ranges/ULongRange/Stdlib.kt",
                      let signature = sema.symbols.functionSignature(for: symbolID),
                      signature.parameterTypes.isEmpty
                else { return false }
                return true
            }
            #expect(isEmptySymbols.count == 1, "Expected one ULongRange.isEmpty() member declaration, got \(isEmptySymbols.count)")
            let expected = Set([
                "contains", "firstOrNull", "lastOrNull", "count",
                "sum", "reversed", "sorted", "toList",
            ])
            var seen = Set<String>()

            for offset in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(offset))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID)
                else { continue }
                let memberName = ctx.interner.resolve(callee)
                guard expected.contains(memberName),
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee
                else { continue }
                let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                let receiverType = try #require(signature.receiverType)
                let (_, receiverSymbol) = try #require(resolveClassTypeSymbol(receiverType, sema: sema))
                #expect(receiverSymbol.fqName == [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("ranges"),
                    ctx.interner.intern("ULongRange"),
                ], "Unexpected receiver for ULongRange.\(memberName): \(ctx.interner.resolve(receiverSymbol.name))")
                #expect(sema.symbols.isSourceBackedSymbol(chosenCallee), "ULongRange.\(memberName) was not source-backed")
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "ULongRange.\(memberName) retained an external link")
                seen.insert(memberName)
            }

            #expect(seen == expected, "Missing source-backed ULongRange members: \(expected.subtracting(seen))")
        }
    }

    @Test
    func ULongRangeAverageIsRejectedLikeKotlin() throws {
        try withTemporaryFile(contents: "fun probe() { (1uL..5uL).average() }") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "ULongRange.average() must be rejected by Sema")
        }
    }

    @Test
    func ULongRangeCallsBindToSourceDefinitions() throws {
        let source = """
        fun probe() {
            (1uL..5uL).forEach { _ -> }
            (1uL..5uL).reduce { accumulator, value -> accumulator + value }
            (1uL..5uL).reduceIndexed { index, accumulator, value -> accumulator + index.toULong() + value }
            (1uL..5uL).fold(10uL) { accumulator, value -> accumulator + value }
            (1uL..5uL).foldIndexed(10uL) { index, accumulator, value -> accumulator + index.toULong() + value }
            (1uL..5uL).find { value -> value % 2uL == 0uL }
            (1uL..5uL).findLast { value -> value % 2uL == 0uL }
            (1uL..5uL).first { value -> value > 1uL }
            (1uL..5uL).firstOrNull { value -> value > 1uL }
            (1uL..5uL).last { value -> value > 1uL }
            (1uL..5uL).lastOrNull { value -> value > 1uL }
            (1uL..5uL).any { value -> value > 1uL }
            (1uL..5uL).all { value -> value > 0uL }
            (1uL..5uL).none { value -> value > 5uL }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected ULongRange HOFs to type-check: \(ctx.diagnostics.diagnostics)")

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
                    Issue.record("Missing ULongRange call binding for \(memberName)")
                    continue
                }
                #expect(sema.symbols.isSourceBackedSymbol(chosenCallee), "Expected ULongRange.\(memberName) to be source-backed")
                let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                let receiverType = try #require(signature.receiverType)
                let (_, receiverSymbol) = try #require(resolveClassTypeSymbol(receiverType, sema: sema))
                #expect(
                    receiverSymbol.fqName == [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("ranges"),
                        ctx.interner.intern("ULongRange"),
                    ],
                    "Unexpected chosen receiver for ULongRange.\(memberName)"
                )
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                seen.insert(memberName)
            }

            #expect(seen == expected, "Missing source-backed ULongRange calls: \(expected.subtracting(seen))")
        }
    }
}
#endif
