#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct RangeUntilSyntheticMemberLinkTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    private func untilSymbols(for sema: SemaModule, interner: StringInterner) -> [SymbolID] {
        sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("ranges"),
            interner.intern("until"),
        ])
    }

    private func classType(
        named name: String,
        in sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let fqName = ["kotlin", "ranges", name].map { interner.intern($0) }
        guard let symbol = sema.symbols.lookup(fqName: fqName) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func intRangeType(in sema: SemaModule, interner: StringInterner) -> TypeID? {
        classType(named: "IntRange", in: sema, interner: interner)
    }

    private func longRangeType(in sema: SemaModule, interner: StringInterner) -> TypeID? {
        classType(named: "LongRange", in: sema, interner: interner)
    }

    private func untilCallExprIDs(
        in ast: ASTModule,
        interner: StringInterner,
        sourceManager: SourceManager
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == "until",
                  // Exclude bundled stdlib source (e.g. kotlin.random.Random's own
                  // `until` usage) so this only counts calls from the test's own
                  // fixture, regardless of how the stdlib itself uses `until`.
                  let range = ast.arena.exprRange(exprID),
                  !sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            else {
                return nil
            }
            return exprID
        }
    }

    @Test func testUntilOverloadsHaveExpectedSignaturesAndLinks() throws {
        let (sema, interner) = try sharedSema()
        let intRange = try #require(intRangeType(in: sema, interner: interner), "IntRange class type")
        let longRange = try #require(longRangeType(in: sema, interner: interner), "LongRange class type")
        let untilSymbolIDs = untilSymbols(for: sema, interner: interner)

        // Bundled Kotlin sources provide class-returning `until` extensions.
        let expected: [(receiver: TypeID, parameter: TypeID, returnType: TypeID)] = [
            (sema.types.intType, sema.types.intType, intRange),
            (sema.types.intType, sema.types.longType, longRange),
            (sema.types.longType, sema.types.intType, longRange),
            (sema.types.longType, sema.types.longType, longRange),
        ]

        for entry in expected {
            let matchingSymbol = untilSymbolIDs.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == entry.receiver
                    && signature.parameterTypes == [entry.parameter]
                    && signature.returnType == entry.returnType
            }
            let symbol = try #require(matchingSymbol, Comment(rawValue: "Expected until overload for \(entry.receiver)"))
            #expect(
                sema.symbols.externalLinkName(for: symbol) == nil,
                Comment(rawValue: "Expected \(entry.receiver).until to be source-backed (no external link)")
            )
        }
    }

    @Test func testUntilInfixCallsResolveToExpectedRuntimeLinksAndRangeKinds() throws {
        let source = """
        fun sample(b: Byte, s: Short, i: Int, l: Long) {
            val byteRange = b until b
            val shortRange = s until s
            val intRange = i until i
            val intLongRange = i until l
            val longIntRange = l until i
            val longRange = l until l
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let untilCalls = untilCallExprIDs(in: ast, interner: ctx.interner, sourceManager: ctx.sourceManager)

        #expect(untilCalls.count == 6)

        let intRange = try #require(intRangeType(in: sema, interner: ctx.interner), "IntRange class type")
        let longRange = try #require(longRangeType(in: sema, interner: ctx.interner), "LongRange class type")

        let expected: [(type: TypeID, link: String?, isUIntRange: Bool, isULongRange: Bool)] = [
            (intRange, nil, false, false),
            (intRange, nil, false, false),
            (intRange, nil, false, false),
            (longRange, nil, false, false),
            (longRange, nil, false, false),
            (longRange, nil, false, false),
        ]

        for (exprID, entry) in zip(untilCalls, expected) {
            let binding = try #require(sema.bindings.callBinding(for: exprID))
            let chosen = binding.chosenCallee
            #expect(
                sema.symbols.externalLinkName(for: chosen) == entry.link,
                Comment(rawValue: "Expected until call to be source-backed (no external link)")
            )
            #expect(
                sema.bindings.exprType(for: exprID) == entry.type,
                "Unexpected inferred type for until call"
            )
            #expect(sema.bindings.isRangeExpr(exprID), "until should mark a range expression")
            #expect(
                sema.bindings.isUIntRangeExpr(exprID) == entry.isUIntRange,
                "Unexpected UInt range marker for until call"
            )
            #expect(
                sema.bindings.isULongRangeExpr(exprID) == entry.isULongRange,
                "Unexpected ULong range marker for until call"
            )
        }
    }
}
#endif
