#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct RangeUntilSyntheticTopLevelLinkTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    private func memberCallExprIDs(named name: String, in ast: ASTModule, interner: StringInterner) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == name
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
        let (sema, interner) = try makeSema()
        let rangeUntilFQName = ["kotlin", "ranges", "rangeUntil"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: rangeUntilFQName)

        #expect(candidates.count == 1, "rangeUntil should register the generic OpenEndRange-returning operator")
        let rangeUntilSymbol = try #require(candidates.first)
        let symbol = try #require(sema.symbols.symbol(rangeUntilSymbol))
        #expect(symbol.flags.contains(.operatorFunction))
        #expect(sema.symbols.externalLinkName(for: rangeUntilSymbol) == "kk_op_rangeUntil")

        let signature = try #require(sema.symbols.functionSignature(for: rangeUntilSymbol))
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

            let rangeUntilCalls = memberCallExprIDs(named: "rangeUntil", in: ast, interner: interner)
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

            let endExclusiveCalls = memberCallExprIDs(named: "endExclusive", in: ast, interner: interner)
            #expect(endExclusiveCalls.count == 1)
            if let endExclusiveCall = endExclusiveCalls.first {
                #expect(sema.bindings.exprType(for: endExclusiveCall) == sema.types.intType)
            }
        }
    }

    @Test func testRangeUntilOverloadMatrixIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let untilFQName = ["kotlin", "ranges", "until"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: untilFQName)

        #expect(candidates.count == 4, "until should register four signed overloads")

        let expectedSignatures: [(receiver: TypeID, parameter: TypeID, returnType: TypeID)] = [
            (sema.types.intType, sema.types.intType, sema.types.intType),
            (sema.types.intType, sema.types.longType, sema.types.longType),
            (sema.types.longType, sema.types.intType, sema.types.longType),
            (sema.types.longType, sema.types.longType, sema.types.longType),
        ]

        for expected in expectedSignatures {
            let v = candidates.contains(where: { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == expected.receiver
                    && signature.parameterTypes == [expected.parameter]
                    && signature.returnType == expected.returnType
            })
            #expect(
                v,
                Comment(rawValue: "Missing until overload receiver=\(sema.types.renderType(expected.receiver)), parameter=\(sema.types.renderType(expected.parameter))")
            )
        }

        let links = Set(candidates.compactMap { sema.symbols.externalLinkName(for: $0) })
        #expect(links == Set(["kk_op_rangeUntil"]), "All until overloads should link to kk_op_rangeUntil")
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

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "until calls should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))")
            )

            let untilCalls = memberCallExprIDs(named: "until", in: ast, interner: interner)
            #expect(untilCalls.count == 5, "Expected five until calls in the sample")

            let expectedUntilSignatures: [(receiver: TypeID, parameter: TypeID, returnType: TypeID)] = [
                (sema.types.intType, sema.types.intType, sema.types.intType),
                (sema.types.intType, sema.types.intType, sema.types.intType),
                (sema.types.intType, sema.types.longType, sema.types.longType),
                (sema.types.longType, sema.types.intType, sema.types.longType),
                (sema.types.longType, sema.types.longType, sema.types.longType),
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
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_op_rangeUntil",
                    "until should lower to kk_op_rangeUntil"
                )
                #expect(
                    sema.bindings.isRangeExpr(callExprID),
                    Comment(rawValue: "until call at index \(index) should be marked as a range expression")
                )
            }

            let countCalls = memberCallExprIDs(named: "count", in: ast, interner: interner)
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
