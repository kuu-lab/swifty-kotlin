#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct RangeIterableExtensionResolutionTests {
    @Test
    func parenthesizedRangesAndInferredProgressionsUseIterableExtensions() throws {
        let source = """
        fun probe() {
            (1..5).elementAt(2)
            (1..5).indexOf(3)
            (1..5).lastIndexOf(3)
            (1..5).asIterable()
            (1..5).asSequence()
            (1..5).toSet()
            (1..5).toMutableList()
            (1..5).joinToString("-")
            (1..5).maxOrNull()
            (1..5).sumOf { it * 2 }
            val longSum: Long = (1..5).sumOf { it.toLong() }
            val doubleSum: Double = (1..5).sumOf { it.toDouble() }
            val uintSum: UInt = (1..5).sumOf { it.toUInt() }
            val ulongSum: ULong = (1..5).sumOf { it.toULong() }
            (1..3).zip(listOf(4, 5, 6))
            (1..3).zip(listOf(4, 5, 6)) { left, right -> left + right }
            (1..3).associateWith { it * 10 }
            (1..5).groupBy { it % 2 }
            val associated: Map<Int, String> = (1..3).associateWith { "$it" }
            val grouped: Map<Int, List<Int>> = (1..5).groupBy { it % 2 }
            (1..5).partition { it % 2 == 0 }
            (1..5).takeWhile { it < 4 }
            (1..5).dropWhile { it < 4 }
            (1..5).count { it % 2 == 1 }
            (1..5).distinct()
            (1..5).sortedDescending()
            (1..3).flatMap { listOf(it, -it) }
            (1..3).flatMap { sequenceOf(it, -it) }
            val flattened: List<Int> = (1..3).flatMap { listOf(it, -it) }
            (1..5).intersect(listOf(2, 4, 6))
            (1..3).union(listOf(3, 4))
            (1..5).subtract(listOf(2, 4))
            (1..3).withIndex()
            (1..5).shuffled()
            (1..3).mapIndexed { index, value -> index + value }
            ('a'..'c').joinToString(",")
            ('a'..'c').joinToString(prefix = "<", postfix = ">")
            ('a'..'e').joinToString("-", "<", ">", 3, "...")

            val progression = 1..10 step 3
            progression.elementAt(2)
            progression.joinToString(",")
            progression.toSet()
            progression.withIndex()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected range Iterable extensions to type-check: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedNames: Set<String> = [
                "elementAt", "indexOf", "lastIndexOf", "asIterable", "asSequence",
                "toSet", "toMutableList", "joinToString", "maxOrNull", "sumOf",
                "zip", "associateWith", "groupBy", "partition", "takeWhile",
                "dropWhile", "count", "distinct", "sortedDescending", "flatMap",
                "intersect", "union", "subtract", "withIndex", "shuffled",
            ]
            let iterableFQName = ["kotlin", "collections", "Iterable"].map(ctx.interner.intern)
            let charRangeFQName = ["kotlin", "ranges", "CharRange"].map(ctx.interner.intern)
            var seen = Set<String>()
            var sawCharRangeJoin = false

            for offset in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(offset))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID)
                else {
                    continue
                }
                let memberName = ctx.interner.resolve(callee)
                guard expectedNames.contains(memberName),
                      let binding = sema.bindings.callBinding(for: exprID)
                else {
                    continue
                }

                let chosen = binding.chosenCallee
                #expect(
                    sema.symbols.isSourceBackedSymbol(chosen),
                    "Expected \(memberName) to bind to bundled Kotlin source"
                )
                let signature = try #require(sema.symbols.functionSignature(for: chosen))
                let receiverType = try #require(signature.receiverType)
                let (_, receiverSymbol) = try #require(resolveClassTypeSymbol(receiverType, sema: sema))
                if memberName == "joinToString" {
                    #expect(
                        receiverSymbol.fqName == iterableFQName || receiverSymbol.fqName == charRangeFQName,
                        "Expected joinToString to use Iterable or the CharRange boxing-preserving overload"
                    )
                    sawCharRangeJoin = sawCharRangeJoin || receiverSymbol.fqName == charRangeFQName
                } else {
                    #expect(
                        receiverSymbol.fqName == iterableFQName,
                        "Expected \(memberName) to use the Iterable extension owner"
                    )
                }
                seen.insert(memberName)
            }

            #expect(seen == expectedNames, "Missing Iterable extension bindings: \(expectedNames.subtracting(seen))")
            #expect(sawCharRangeJoin, "Expected CharRange.joinToString to preserve character boxing")
        }
    }

    @Test
    func exactRangeExtensionsKeepTheirRangeOwner() throws {
        let source = """
        fun probe() {
            (1..5).map { it * 2 }
            (1..3).mapIndexed { index, value -> index + value }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected range HOF calls to type-check: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedNames = Set(["map", "mapIndexed"])
            var seen = Set<String>()
            for offset in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(offset))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID),
                      expectedNames.contains(ctx.interner.resolve(callee)),
                      let binding = sema.bindings.callBinding(for: exprID),
                      let signature = sema.symbols.functionSignature(for: binding.chosenCallee),
                      let receiverType = signature.receiverType,
                      let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema)
                else {
                    continue
                }
                #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
                #expect(receiverSymbol.fqName.map(ctx.interner.resolve) == ["kotlin", "ranges", "IntRange"])
                seen.insert(ctx.interner.resolve(callee))
            }

            #expect(seen == expectedNames, "Missing exact range bindings: \(expectedNames.subtracting(seen))")
        }
    }

    @Test
    func unrelatedRangeMembersKeepTheirExistingFallbackRouting() throws {
        let source = """
        fun probe() {
            (1..5).first
            (1..5).last
            (1..5).count()
            (1..5).reversed()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected existing range members to keep type-checking")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedNames = Set(["first", "last", "count", "reversed"])
            var seen = Set<String>()
            for offset in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(offset))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID)
                else {
                    continue
                }
                let memberName = ctx.interner.resolve(callee)
                guard expectedNames.contains(memberName) else {
                    continue
                }
                #expect(
                    sema.bindings.callBinding(for: exprID) == nil,
                    "Expected \(memberName) to stay on its pre-KUU-569 fallback route"
                )
                seen.insert(memberName)
            }
            #expect(seen == expectedNames)
        }
    }

    @Test
    func rangeToPrimitiveArrayRemainsUnsupported() throws {
        let source = """
        fun probe() {
            (1..5).toIntArray()
            (1..5 step 2).toIntArray()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.filter { diagnostic in
                diagnostic.code == "KSWIFTK-SEMA-0024"
                    && diagnostic.message == "Unresolved member function 'toIntArray'."
            }
            #expect(diagnostics.count == 2)
        }
    }

    @Test
    func scopedCharRangeJoinExtensionKeepsPriority() throws {
        let source = """
        fun CharRange.joinToString(separator: CharSequence): String = "user:$separator"

        fun probe(): String = ('a'..'c').joinToString("|")
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected scoped CharRange extension to type-check")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(ast.arena.exprs.indices.lazy.compactMap { offset -> ExprID? in
                let exprID = ExprID(rawValue: Int32(offset))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID),
                      ctx.interner.resolve(callee) == "joinToString"
                else {
                    return nil
                }
                return exprID
            }.first)
            let binding = try #require(sema.bindings.callBinding(for: call))
            let sourceFile = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
            #expect(ctx.sourceManager.path(of: sourceFile) == path)
        }
    }
}
#endif
