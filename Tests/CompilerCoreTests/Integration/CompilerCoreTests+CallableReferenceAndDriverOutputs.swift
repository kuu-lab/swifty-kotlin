#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension CompilerCoreTests {
    @Test func testCallableReferenceAndDriverOutputs() throws {
        let sources: [String] = [
            // source 0: no-arg lambda initializer parses as .lambdaLiteral
            """
            package sample0
            fun host0() {
                val f0: () -> Int = { 42 }
            }
            """,

            // source 1: lambda inference, capture, and local callable call
            """
            package sample1
            fun host1(seed: Int): Int {
                val offset = seed
                val add: (Int) -> Int = { value -> value + offset }
                return add(1)
            }
            """,

            // source 2/3: import alias preserves alias
            """
            package lib0
            fun helper0(x: Int) = x
            """,
            """
            package app0
            import lib0.helper0 as h0
            fun use0() = h0(1)
            """,

            // source 4/5: non-aliased import has nil alias
            """
            package lib1
            fun helper1(x: Int) = x
            """,
            """
            package app1
            import lib1.helper1
            fun use1() = helper1(1)
            """,

            // source 6: callable reference infers function type and binds target
            """
            package sample6
            fun target6(x: Int): Int = x + 1
            fun use6(): Int {
                val ref: (Int) -> Int = ::target6
                return ref(1)
            }
            """,

            // source 7: bound callable reference captures receiver
            """
            package sample7
            fun Int.incByOne7(): Int = this + 1
            fun host7(seed: Int): Int {
                val ref: () -> Int = seed::incByOne7
                return ref()
            }
            """,

            // source 8: overloaded callable reference selects deterministic target
            """
            package sample8
            fun target8(x: String): String = x
            fun target8(x: Int): Int = x + 1
            fun use8(): Int {
                val ref: (Int) -> Int = ::target8
                return ref(1)
            }
            """,

            // source 9: direct callable reference call propagates target binding
            """
            package sample9
            fun target9(x: String): String = x
            fun target9(x: Int): Int = x + 1
            fun use9(): Int = (::target9)(1)
            """,

            // source 10: function type parameter uses callable value resolution
            """
            package sample10
            fun apply10(f: (Int) -> Int, x: Int): Int = f(x)
            """,

            // source 11: property callable reference uses property type
            """
            package sample11
            val answer11: Int = 42
            fun use11(): Int {
                val ref = ::answer11
                return answer11
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let intType = sema.types.make(.primitive(.int, .nonNull))

            let sourceFileIDs = try paths.map { path in
                try #require(ctx.sourceManager.fileID(forPath: path))
            }

            // MARK: - 0. No-arg lambda initializer builds lambda literal
            do {
                let sourceFileID = sourceFileIDs[0]
                let localDeclExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { return false }
                    if case .localDecl = expr { return true } else { return false }
                })
                let localDeclExpr = try #require(ast.arena.expr(localDeclExprID))
                guard case let .localDecl(_, _, _, initializer, _, _) = localDeclExpr,
                      let initializerExprID = initializer,
                      let initializerExpr = ast.arena.expr(initializerExprID)
                else {
                    Issue.record("Expected local declaration initializer.")
                    return
                }
                guard case .lambdaLiteral = initializerExpr else {
                    Issue.record("Expected zero-argument lambda initializer to parse as .lambdaLiteral.")
                    return
                }
            }

            // MARK: - 1. No-arg lambda infers explicit function type
            do {
                let sourceFileID = sourceFileIDs[0]
                let lambdaExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { return false }
                    if case .lambdaLiteral = expr { return true } else { return false }
                })
                let lambdaType = try #require(sema.bindings.exprTypes[lambdaExprID])
                guard case let .functionType(functionType) = sema.types.kind(of: lambdaType) else {
                    Issue.record("Expected lambda to infer a function type.")
                    return
                }
                #expect(functionType.params.isEmpty)
                #expect(functionType.returnType == intType)
            }

            // MARK: - 2. Lambda captures outer local and resolves local callable call
            do {
                let sourceFileID = sourceFileIDs[1]
                let lambdaExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { return false }
                    if case .lambdaLiteral = expr { return true } else { return false }
                })
                let addCallExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { return false }
                    guard case let .call(calleeExprID, _, _, _) = expr,
                          let calleeExpr = ast.arena.expr(calleeExprID),
                          case let .nameRef(calleeName, _) = calleeExpr
                    else {
                        return false
                    }
                    return ctx.interner.resolve(calleeName) == "add"
                })

                let lambdaType = try #require(sema.bindings.exprTypes[lambdaExprID])
                guard case let .functionType(functionType) = sema.types.kind(of: lambdaType) else {
                    Issue.record("Lambda should infer function type.")
                    return
                }
                #expect(functionType.params == [intType])
                #expect(functionType.returnType == intType)

                let offsetSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    guard symbol.kind == .local, ctx.interner.resolve(symbol.name) == "offset" else { return false }
                    guard let declSite = symbol.declSite else { return false }
                    return declSite.start.file == sourceFileID
                })?.id)
                #expect(sema.bindings.captureSymbolsByExpr[lambdaExprID] == [offsetSymbol])
                #expect(sema.bindings.callableValueCalls[addCallExprID] != nil)
            }

            // MARK: - 3. Import alias preserves alias field
            do {
                let appFile = try #require(ast.files.first(where: { file in
                    file.packageFQName.map { ctx.interner.resolve($0) } == ["app0"]
                }))
                let aliasedImport = try #require(appFile.imports.first(where: { importDecl in
                    importDecl.alias != nil
                }))
                #expect(try ctx.interner.resolve(#require(aliasedImport.alias)) == "h0")
                #expect(aliasedImport.path.map { ctx.interner.resolve($0) } == ["lib0", "helper0"])
            }

            // MARK: - 4. Non-aliased import has nil alias
            do {
                let appFile = try #require(ast.files.first(where: { file in
                    file.packageFQName.map { ctx.interner.resolve($0) } == ["app1"]
                }))
                let regularImport = try #require(appFile.imports.first)
                #expect(regularImport.alias == nil)
            }

            // MARK: - 5. Callable reference infers function type and binds target
            do {
                let sourceFileID = sourceFileIDs[6]
                let callableRefExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { return false }
                    if case .callableRef = expr { return true } else { return false }
                })
                let refCallExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { return false }
                    guard case let .call(calleeExprID, _, _, _) = expr,
                          let calleeExpr = ast.arena.expr(calleeExprID),
                          case let .nameRef(calleeName, _) = calleeExpr
                    else {
                        return false
                    }
                    return ctx.interner.resolve(calleeName) == "ref"
                })
                let targetSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    symbol.kind == .function && ctx.interner.resolve(symbol.name) == "target6"
                })?.id)

                #expect(sema.bindings.identifierSymbols[callableRefExprID] == targetSymbol)
                #expect(sema.bindings.callableTargets[callableRefExprID] == .symbol(targetSymbol))
                #expect(sema.bindings.captureSymbolsByExpr[callableRefExprID] == [])

                let refType = try #require(sema.bindings.exprTypes[callableRefExprID])
                guard case let .functionType(functionType) = sema.types.kind(of: refType) else {
                    Issue.record("Callable reference should infer function type.")
                    return
                }
                #expect(functionType.params == [intType])
                #expect(functionType.returnType == intType)
                #expect(sema.bindings.callableValueCalls[refCallExprID] != nil)
            }

            // MARK: - 6. Bound callable reference captures receiver
            do {
                let sourceFileID = sourceFileIDs[7]
                let callableRefExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { return false }
                    if case .callableRef = expr { return true } else { return false }
                })
                let extensionSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    symbol.kind == .function && ctx.interner.resolve(symbol.name) == "incByOne7"
                })?.id)
                let capturedSymbols = try #require(sema.bindings.captureSymbolsByExpr[callableRefExprID])
                #expect(capturedSymbols.count == 1)
                let seedSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    guard symbol.kind == .valueParameter,
                          ctx.interner.resolve(symbol.name) == "seed"
                    else {
                        return false
                    }
                    let fqName = symbol.fqName.map(ctx.interner.resolve)
                    return fqName.contains("host7")
                })?.id)
                #expect(capturedSymbols == [seedSymbol])

                #expect(sema.bindings.callableTargets[callableRefExprID] == .symbol(extensionSymbol))
                #expect(sema.bindings.captureSymbolsByExpr[callableRefExprID] == [seedSymbol])

                let callableType = try #require(sema.bindings.exprTypes[callableRefExprID])
                guard case let .functionType(functionType) = sema.types.kind(of: callableType) else {
                    Issue.record("Bound callable reference should infer function type.")
                    return
                }
                #expect(functionType.params.count == 0)
                #expect(functionType.returnType == intType)
            }

            // MARK: - 7. Overloaded callable reference selects deterministic target
            do {
                let sourceFileID = sourceFileIDs[8]
                let callableRefExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { return false }
                    if case .callableRef = expr { return true } else { return false }
                })

                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-0003", in: ctx)

                let intOverloadSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    guard symbol.kind == .function,
                          ctx.interner.resolve(symbol.name) == "target8",
                          let signature = sema.symbols.functionSignature(for: symbol.id),
                          signature.parameterTypes.count == 1,
                          signature.parameterTypes[0] == intType
                    else {
                        return false
                    }
                    return true
                })?.id)

                #expect(sema.bindings.identifierSymbols[callableRefExprID] == intOverloadSymbol)
                #expect(sema.bindings.callableTargets[callableRefExprID] == .symbol(intOverloadSymbol))
            }

            // MARK: - 8. Direct callable reference call propagates target binding
            do {
                let sourceFileID = sourceFileIDs[9]

                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-0003", in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)

                let intOverloadSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    guard symbol.kind == .function,
                          ctx.interner.resolve(symbol.name) == "target9",
                          let signature = sema.symbols.functionSignature(for: symbol.id),
                          signature.parameterTypes.count == 1,
                          signature.parameterTypes[0] == intType
                    else {
                        return false
                    }
                    return true
                })?.id)
                let callExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { return false }
                    guard case let .call(calleeExprID, _, _, _) = expr,
                          let calleeExpr = ast.arena.expr(calleeExprID)
                    else {
                        return false
                    }
                    if case .callableRef = calleeExpr { return true } else { return false }
                })

                let callBinding = try #require(sema.bindings.callableValueCalls[callExprID])
                #expect(callBinding.target == .symbol(intOverloadSymbol))
                #expect(callBinding.parameterMapping == [0: 0])
                #expect(sema.bindings.callableTargets[callExprID] == .symbol(intOverloadSymbol))
            }

            // MARK: - 9. Function type parameter call uses callable value resolution
            do {
                let sourceFileID = sourceFileIDs[10]

                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

                let callExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { return false }
                    guard case let .call(calleeExprID, _, _, _) = expr,
                          let calleeExpr = ast.arena.expr(calleeExprID),
                          case let .nameRef(calleeName, _) = calleeExpr
                    else {
                        return false
                    }
                    return ctx.interner.resolve(calleeName) == "f"
                })
                let callableCallBinding = try #require(sema.bindings.callableValueCalls[callExprID])
                guard case let .localValue(fParamSymbol) = callableCallBinding.target else {
                    Issue.record("Callable value call should target the function-typed parameter f.")
                    return
                }
                let fParam = try #require(sema.symbols.symbol(fParamSymbol))
                #expect(fParam.kind == .valueParameter)
                #expect(ctx.interner.resolve(fParam.name) == "f")
                #expect(callableCallBinding.parameterMapping == [0: 0])

                guard case let .functionType(functionType) = sema.types.kind(of: callableCallBinding.functionType) else {
                    Issue.record("Callable value call binding should store function type.")
                    return
                }
                #expect(functionType.params == [intType])
                #expect(functionType.returnType == intType)
            }

            // MARK: - 10. Property callable reference uses property type for fallback binding
            do {
                let sourceFileID = sourceFileIDs[11]
                let callableRefExprID = try #require(firstExprID(in: ast) { exprID, expr in
                    guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { return false }
                    if case .callableRef = expr { return true } else { return false }
                })
                let answerSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    symbol.kind == .property && ctx.interner.resolve(symbol.name) == "answer11"
                })?.id)

                #expect(sema.bindings.identifierSymbols[callableRefExprID] == answerSymbol)
                #expect(sema.bindings.exprTypes[callableRefExprID] == sema.symbols.propertyType(for: answerSymbol))
            }
        }
    }
}
#endif
