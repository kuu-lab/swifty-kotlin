#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct RangeUntilSyntheticTopLevelLinkTests {
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

    private func rangeType(
        for elementType: TypeID,
        in sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let name: String
        if elementType == sema.types.longType {
            name = "LongRange"
        } else if elementType == sema.types.charType {
            name = "CharRange"
        } else if elementType == sema.types.uintType {
            name = "UIntRange"
        } else if elementType == sema.types.ulongType {
            name = "ULongRange"
        } else {
            name = "IntRange"
        }
        return classType(named: name, in: sema, interner: interner)
    }

    private func memberCallExprIDs(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner,
        sourceManager: SourceManager
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == name,
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

    private func assertOpenEndRange(
        _ type: TypeID,
        elementType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard case let .classType(classType) = sema.types.kind(of: type),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            Issue.record(Comment(rawValue: "Expected OpenEndRange class type, got \(sema.types.renderType(type))"))
            return
        }
        #expect(interner.resolve(symbol.name) == "OpenEndRange")
        #expect(classType.args.count == 1)
        guard let argument = classType.args.first else {
            return
        }
        switch argument {
        case let .invariant(actual), let .out(actual), let .in(actual):
            #expect(actual == elementType)
        case .star:
            Issue.record("Expected concrete OpenEndRange type argument")
        }
    }

    @Test func testRangeUntilOperatorSurfaceReturnsOpenEndRange() throws {
        let (sema, interner) = try sharedSema()
        let rangeUntilFQName = ["kotlin", "ranges", "rangeUntil"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: rangeUntilFQName)

        // Bundled Kotlin sources provide concrete `rangeUntil` overloads, plus
        // the legacy generic `operator fun <T : Comparable<T>> T.rangeUntil(that: T)`.
        #expect(!candidates.isEmpty, "rangeUntil should be registered")

        let genericRangeUntil = try #require(
            candidates.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.typeParameterSymbols.count == 1
            },
            "Expected a generic rangeUntil operator"
        )
        let symbol = try #require(sema.symbols.symbol(genericRangeUntil))
        #expect(symbol.flags.contains(.operatorFunction))
        #expect(sema.symbols.externalLinkName(for: genericRangeUntil) == "__kk_op_rangeUntil")

        let signature = try #require(sema.symbols.functionSignature(for: genericRangeUntil))
        #expect(signature.typeParameterSymbols.count == 1)
        let typeParameter = try #require(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        #expect(signature.receiverType == typeParameterType)
        #expect(signature.parameterTypes == [typeParameterType])
        try assertOpenEndRange(
            signature.returnType,
            elementType: typeParameterType,
            sema: sema,
            interner: interner
        )

        let concreteCount = candidates.filter { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.typeParameterSymbols.isEmpty
        }.count
        #expect(concreteCount == 19, "Expected 19 concrete rangeUntil overloads")
    }

    @Test func testRangeUntilCallReturnsOpenEndRangeAndEndExclusiveResolves() throws {
        let source = """
        fun sample(): Int {
            val range = 0.rangeUntil(10)
            return range.endExclusive
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "rangeUntil should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))")
            )
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let rangeUntilCalls = memberCallExprIDs(named: "rangeUntil", in: ast, interner: interner, sourceManager: ctx.sourceManager)
            #expect(rangeUntilCalls.count == 1)
            let rangeUntilCall = try #require(rangeUntilCalls.first)
            let rangeUntilType = try #require(sema.bindings.exprType(for: rangeUntilCall))
            try assertOpenEndRange(
                rangeUntilType,
                elementType: sema.types.intType,
                sema: sema,
                interner: interner
            )
            #expect(sema.bindings.isRangeExpr(rangeUntilCall))

            let endExclusiveCalls = memberCallExprIDs(named: "endExclusive", in: ast, interner: interner, sourceManager: ctx.sourceManager)
            #expect(endExclusiveCalls.count == 1)
            if let endExclusiveCall = endExclusiveCalls.first {
                #expect(sema.bindings.exprType(for: endExclusiveCall) == sema.types.intType)
            }
        }
    }

    @Test func testRangeUntilOverloadMatrixIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let untilFQName = ["kotlin", "ranges", "until"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: untilFQName)

        // Bundled Kotlin sources provide `until` overloads for Byte/Short/Int/Long
        // (16 combinations), Char, UInt, and ULong.
        let signedUntilTypes = [
            sema.types.byteType,
            sema.types.shortType,
            sema.types.intType,
            sema.types.longType,
        ]
        let extraUntilTypes: [(TypeID, TypeID)] = [
            (sema.types.charType, sema.types.charType),
            (sema.types.uintType, sema.types.uintType),
            (sema.types.ulongType, sema.types.ulongType),
        ]

        var expectedSignatures: [(receiver: TypeID, parameter: TypeID, returnType: TypeID)] = []
        for receiver in signedUntilTypes {
            for parameter in signedUntilTypes {
                let returnType: TypeID = if receiver == sema.types.longType || parameter == sema.types.longType {
                    sema.types.longType
                } else {
                    sema.types.intType
                }
                expectedSignatures.append((receiver, parameter, returnType))
            }
        }
        for (receiver, parameter) in extraUntilTypes {
            expectedSignatures.append((receiver, parameter, receiver))
        }

        #expect(
            candidates.count == expectedSignatures.count,
            "until should register the full overload matrix (got \(candidates.count), expected \(expectedSignatures.count))"
        )

        for expected in expectedSignatures {
            let expectedReturnType = try #require(
                rangeType(for: expected.returnType, in: sema, interner: interner),
                "Range class for \(sema.types.renderType(expected.returnType))"
            )
            let v = candidates.contains(where: { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == expected.receiver
                    && signature.parameterTypes == [expected.parameter]
                    && signature.returnType == expectedReturnType
            })
            #expect(
                v,
                Comment(rawValue: "Missing until overload receiver=\(sema.types.renderType(expected.receiver)), parameter=\(sema.types.renderType(expected.parameter))")
            )
        }

        // All public `until` overloads are source-backed; the bridge stays behind
        // the `__rangeUntil` internal external functions.
        let links = Set(candidates.compactMap { sema.symbols.externalLinkName(for: $0) })
        #expect(links.isEmpty, "until overloads should be source-backed (no external link)")
    }

    @Test func testMixedWidthUntilCallsResolveAndRemainRangeExpressions() throws {
        let source = """
        fun sample(): Int {
            val bb = 1.toByte() until 2.toByte()
            val ss = 1.toShort() until 2.toShort()
            val bl = 1.toByte() until 2L
            val lb = 1L until 2.toShort()
            val ll = 1L until 2L
            return bb.count() + ss.count() + bl.count() + lb.count() + ll.count()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "until calls should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))")
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let untilCalls = memberCallExprIDs(named: "until", in: ast, interner: interner, sourceManager: ctx.sourceManager)
            #expect(untilCalls.count == 5, "Expected five until calls in the sample")

            let intRange = try #require(classType(named: "IntRange", in: sema, interner: interner))
            let longRange = try #require(classType(named: "LongRange", in: sema, interner: interner))
            let expectedUntilSignatures: [(receiver: TypeID, parameter: TypeID, returnType: TypeID)] = [
                // bb = 1.toByte() until 2.toByte()
                (sema.types.byteType, sema.types.byteType, intRange),
                // ss = 1.toShort() until 2.toShort()
                (sema.types.shortType, sema.types.shortType, intRange),
                // bl = 1.toByte() until 2L
                (sema.types.byteType, sema.types.longType, longRange),
                // lb = 1L until 2.toShort()
                (sema.types.longType, sema.types.shortType, longRange),
                // ll = 1L until 2L
                (sema.types.longType, sema.types.longType, longRange),
            ]

            for (index, callExprID) in untilCalls.enumerated() {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExprID)?.chosenCallee,
                    Comment(rawValue: "Expected a chosen callee for until call at index \(index)")
                )
                let signature = try #require(
                    sema.symbols.functionSignature(for: chosenCallee),
                    Comment(rawValue: "Expected a function signature for until call at index \(index)")
                )
                let expected = expectedUntilSignatures[index]
                #expect(
                    signature.receiverType == expected.receiver,
                    Comment(rawValue: "Unexpected until receiver type at index \(index)")
                )
                #expect(
                    signature.parameterTypes == [expected.parameter],
                    Comment(rawValue: "Unexpected until parameter type at index \(index)")
                )
                #expect(
                    signature.returnType == expected.returnType,
                    Comment(rawValue: "Unexpected until return type at index \(index)")
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == nil,
                    "until should be source-backed (no external link)"
                )
                #expect(
                    sema.bindings.isRangeExpr(callExprID),
                    Comment(rawValue: "until call at index \(index) should be marked as a range expression")
                )
            }

            let countCalls = memberCallExprIDs(named: "count", in: ast, interner: interner, sourceManager: ctx.sourceManager)
            #expect(countCalls.count == 5, "Expected five count calls in the sample")
            for (index, countCallID) in countCalls.enumerated() {
                #expect(
                    sema.bindings.exprTypes[countCallID] == sema.types.intType,
                    Comment(rawValue: "count() should infer Int at index \(index)")
                )
                if case let .memberCall(receiverExprID, _, _, _, _) = ast.arena.expr(countCallID) {
                    #expect(
                        sema.bindings.isRangeExpr(receiverExprID),
                        Comment(rawValue: "count() receiver at index \(index) should remain marked as a range")
                    )
                } else {
                    Issue.record(Comment(rawValue: "Expected a memberCall expression for count at index \(index)"))
                }
            }
        }
    }
}
#endif
