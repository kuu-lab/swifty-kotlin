#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension CompilerCoreTests {
    @Test func testNoArgLambdaInitializerBuildsLambdaLiteral() throws {
        let source = """
        fun host() {
            val f0: () -> Int = { 42 }
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let localDeclExprID = try #require(firstExprID(in: ast) { _, expr in
            guard case .localDecl = expr else { return false }
            return true
        })
        guard case let .localDecl(_, _, _, initializer, _, _) = try #require(ast.arena.expr(localDeclExprID)),
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

    @Test func testNoArgLambdaInitializerInfersExplicitFunctionType() throws {
        let source = """
        fun host() {
            val f0: () -> Int = { 42 }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no sema errors, got: \(ctx.diagnostics.diagnostics.map { $0.message })"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let lambdaExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .lambdaLiteral = expr { return true }
            return false
        })
        let lambdaType = try #require(sema.bindings.exprTypes[lambdaExprID])
        guard case let .functionType(functionType) = sema.types.kind(of: lambdaType) else {
            Issue.record("Expected lambda to infer a function type.")
            return
        }

        #expect(functionType.params.isEmpty)
        #expect(functionType.returnType == sema.types.intType)
    }

    @Test func testImportAliasBuildASTPreservesAliasField() throws {
        let sources = [
            """
            package lib
            fun helper(x: Int) = x
            """,
            """
            package app
            import lib.helper as h
            fun use() = h(1)
            """,
        ]
        let ctx = makeContextFromSources(sources)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let appFile = try #require(ast.files.first(where: { file in
            file.packageFQName.map { ctx.interner.resolve($0) } == ["app"]
        }))
        let aliasedImport = try #require(appFile.imports.first(where: { importDecl in
            importDecl.alias != nil
        }))
        #expect(try ctx.interner.resolve(#require(aliasedImport.alias)) == "h")
        #expect(aliasedImport.path.map { ctx.interner.resolve($0) } == ["lib", "helper"])
    }

    @Test func testImportAliasNonAliasedImportHasNilAlias() throws {
        let sources = [
            """
            package lib
            fun helper(x: Int) = x
            """,
            """
            package app
            import lib.helper
            fun use() = helper(1)
            """,
        ]
        let ctx = makeContextFromSources(sources)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let appFile = try #require(ast.files.first(where: { file in
            file.packageFQName.map { ctx.interner.resolve($0) } == ["app"]
        }))
        let regularImport = try #require(appFile.imports.first)
        #expect(regularImport.alias == nil)
    }

    @Test func testLambdaInferenceCapturesOuterLocalAndResolvesLocalCallableCall() throws {
        let source = """
        fun host(seed: Int): Int {
            val offset = seed
            val add: (Int) -> Int = { value -> value + offset }
            return add(1)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let lambdaExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .lambdaLiteral = expr { return true }
            return false
        })
        let addCallExprID = try #require(firstExprID(in: ast) { _, expr in
            guard case let .call(calleeExprID, _, _, _) = expr,
                  let calleeExpr = ast.arena.expr(calleeExprID),
                  case let .nameRef(calleeName, _) = calleeExpr
            else {
                return false
            }
            return ctx.interner.resolve(calleeName) == "add"
        })

        let lambdaType = try #require(sema.bindings.exprTypes[lambdaExprID])
        let intType = sema.types.make(.primitive(.int, .nonNull))
        guard case let .functionType(functionType) = sema.types.kind(of: lambdaType) else {
            Issue.record("Lambda should infer function type.")
            return
        }
        #expect(functionType.params == [intType])
        #expect(functionType.returnType == intType)

        let offsetSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .local && ctx.interner.resolve(symbol.name) == "offset"
        })?.id)
        #expect(sema.bindings.captureSymbolsByExpr[lambdaExprID] == [offsetSymbol])
        #expect(sema.bindings.callableValueCalls[addCallExprID] != nil)
    }

    @Test func testCallableReferenceInfersFunctionTypeAndBindsTargetSymbol() throws {
        let source = """
        fun target(x: Int): Int = x + 1
        fun use(): Int {
            val ref: (Int) -> Int = ::target
            return ref(1)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let refCallExprID = try #require(firstExprID(in: ast) { _, expr in
            guard case let .call(calleeExprID, _, _, _) = expr,
                  let calleeExpr = ast.arena.expr(calleeExprID),
                  case let .nameRef(calleeName, _) = calleeExpr
            else {
                return false
            }
            return ctx.interner.resolve(calleeName) == "ref"
        })
        let targetSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .function && ctx.interner.resolve(symbol.name) == "target"
        })?.id)

        #expect(sema.bindings.identifierSymbols[callableRefExprID] == targetSymbol)
        #expect(sema.bindings.callableTargets[callableRefExprID] == .symbol(targetSymbol))
        #expect(sema.bindings.captureSymbolsByExpr[callableRefExprID] == [])

        let refType = try #require(sema.bindings.exprTypes[callableRefExprID])
        let intType = sema.types.make(.primitive(.int, .nonNull))
        guard case let .functionType(functionType) = sema.types.kind(of: refType) else {
            Issue.record("Callable reference should infer function type.")
            return
        }
        #expect(functionType.params == [intType])
        #expect(functionType.returnType == intType)
        #expect(sema.bindings.callableValueCalls[refCallExprID] != nil)
    }

    @Test func testBoundCallableReferenceCapturesReceiverAndResolvesExtensionTarget() throws {
        let source = """
        fun Int.incByOne(): Int = this + 1
        fun host(seed: Int): Int {
            val ref: () -> Int = seed::incByOne
            return ref()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let extensionSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .function && ctx.interner.resolve(symbol.name) == "incByOne"
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
            return fqName.contains("host")
        })?.id)
        #expect(capturedSymbols == [seedSymbol])

        #expect(sema.bindings.callableTargets[callableRefExprID] == .symbol(extensionSymbol))
        #expect(sema.bindings.captureSymbolsByExpr[callableRefExprID] == [seedSymbol])

        let callableType = try #require(sema.bindings.exprTypes[callableRefExprID])
        let intType = sema.types.make(.primitive(.int, .nonNull))
        guard case let .functionType(functionType) = sema.types.kind(of: callableType) else {
            Issue.record("Bound callable reference should infer function type.")
            return
        }
        #expect(functionType.params.count == 0)
        #expect(functionType.returnType == intType)
    }

    @Test func testCallableReferenceOverloadSelectionBindsDeterministicTargetSymbol() throws {
        let source = """
        fun target(x: String): String = x
        fun target(x: Int): Int = x + 1
        fun use(): Int {
            val ref: (Int) -> Int = ::target
            return ref(1)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0003", in: ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let intOverloadSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            guard symbol.kind == .function,
                  ctx.interner.resolve(symbol.name) == "target",
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

    @Test func testDirectCallableReferenceCallPropagatesSymbolTargetBinding() throws {
        let source = """
        fun target(x: String): String = x
        fun target(x: Int): Int = x + 1
        fun use(): Int = (::target)(1)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0003", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let intOverloadSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            guard symbol.kind == .function,
                  ctx.interner.resolve(symbol.name) == "target",
                  let signature = sema.symbols.functionSignature(for: symbol.id),
                  signature.parameterTypes.count == 1,
                  signature.parameterTypes[0] == intType
            else {
                return false
            }
            return true
        })?.id)
        let callExprID = try #require(firstExprID(in: ast) { _, expr in
            guard case let .call(calleeExprID, _, _, _) = expr,
                  let calleeExpr = ast.arena.expr(calleeExprID)
            else {
                return false
            }
            if case .callableRef = calleeExpr {
                return true
            }
            return false
        })

        let callBinding = try #require(sema.bindings.callableValueCalls[callExprID])
        #expect(callBinding.target == .symbol(intOverloadSymbol))
        #expect(callBinding.parameterMapping == [0: 0])
        #expect(sema.bindings.callableTargets[callExprID] == .symbol(intOverloadSymbol))
    }

    @Test func testFunctionTypeParameterCallUsesCallableValueResolution() throws {
        let source = """
        fun apply(f: (Int) -> Int, x: Int): Int = f(x)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExprID = try #require(firstExprID(in: ast) { _, expr in
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

        let intType = sema.types.make(.primitive(.int, .nonNull))
        guard case let .functionType(functionType) = sema.types.kind(of: callableCallBinding.functionType) else {
            Issue.record("Callable value call binding should store function type.")
            return
        }
        #expect(functionType.params == [intType])
        #expect(functionType.returnType == intType)
    }

    @Test func testPropertyCallableReferenceUsesPropertyTypeForFallbackBinding() throws {
        let source = """
        val answer: Int = 42
        fun use(): Int {
            val ref = ::answer
            return answer
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let answerSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .property && ctx.interner.resolve(symbol.name) == "answer"
        })?.id)

        #expect(sema.bindings.identifierSymbols[callableRefExprID] == answerSymbol)
        #expect(sema.bindings.exprTypes[callableRefExprID] == sema.symbols.propertyType(for: answerSymbol))
    }
}
#endif
