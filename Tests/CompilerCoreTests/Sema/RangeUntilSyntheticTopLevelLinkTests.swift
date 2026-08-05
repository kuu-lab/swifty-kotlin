#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct RangeUntilSyntheticTopLevelLinkTests {
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

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        diagnosticsForPath(path, in: ctx).filter { $0.code == code }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func lastExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        var result: ExprID?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { result = exprID }
        }
        return result
    }

    private func allExprIDsInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func memberCallExprIDsInPath(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

    private func firstUserObjectLiteralDeclIDInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager
    ) -> DeclID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  let range = ast.arena.exprRange(exprID),
                  sourceManager.path(of: range.start.file) == path
            else { continue }
            return declID
        }
        return nil
    }

    private func findMainBodyStatementsInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> [ExprID]? {
        guard let fileID = sourceManager.fileID(forPath: path) else { return nil }
        for file in ast.files {
            guard file.fileID == fileID else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testRangeUntilOperatorSurfaceReturnsOpenEndRange
            """
            package sample0
            fun noop() {}
            """,
            // testRangeUntilCallReturnsOpenEndRangeAndEndExclusiveResolves
            """
            package sample1

                    fun sample(): Int {
                        val range = 0.rangeUntil(10)
                        return range.endExclusive
                    }

            """,
            // testRangeUntilOverloadMatrixIsRegistered
            """
            package sample2
            fun noop() {}
            """,
            // testMixedWidthUntilCallsResolveAndRemainRangeExpressions
            """
            package sample3

                    fun sample(): Int {
                        val bb = 1.toByte() until 2.toByte()
                        val ss = 1.toShort() until 2.toShort()
                        val bl = 1.toByte() until 2L
                        val lb = 1L until 2.toShort()
                        val ll = 1L until 2L
                        return bb.count() + ss.count() + bl.count() + lb.count() + ll.count()
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testRangeUntilOperatorSurfaceReturnsOpenEndRange ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

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

            // === testRangeUntilCallReturnsOpenEndRangeAndEndExclusiveResolves ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(
                    !(sample1Diagnostics.contains { $0.severity == .error }),
                    Comment(rawValue: "rangeUntil should resolve without diagnostics: \(sample1Diagnostics.map(\.message))")
                )

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

            // === testRangeUntilOverloadMatrixIsRegistered ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

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

            // === testMixedWidthUntilCallsResolveAndRemainRangeExpressions ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                #expect(
                    !(sample3Diagnostics.contains { $0.severity == .error }),
                    Comment(rawValue: "until calls should resolve without diagnostics: \(sample3Diagnostics.map(\.message))")
                )

                let untilCalls = memberCallExprIDs(named: "until", in: ast, interner: interner, sourceManager: ctx.sourceManager)
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

}

#endif
