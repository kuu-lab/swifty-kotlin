@testable import CompilerCore
import Foundation
import XCTest

extension LoweringPassRegressionTests {

    // MARK: - INLINE-002: Lambda argument inlining

    /// Verify that a lambda passed to an inline function is expanded in place,
    /// eliminating the indirect call to the lambda function.
    func testInlineLoweringInlinesLambdaArgumentBody() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let diagnostics = DiagnosticEngine()

        let intType = types.make(.primitive(.int, .nonNull))
        let funcType = types.make(.functionType(FunctionType(
            params: [intType],
            returnType: intType
        )))

        // Define symbols
        let mainSymbol = symbols.define(
            kind: .function,
            name: interner.intern("main"),
            fqName: [interner.intern("test"), interner.intern("main")],
            declSite: nil,
            visibility: .public
        )
        let inlineSymbol = symbols.define(
            kind: .function,
            name: interner.intern("applyBlock"),
            fqName: [interner.intern("test"), interner.intern("applyBlock")],
            declSite: nil,
            visibility: .public,
            flags: [.inlineFunction]
        )
        let inlineValueParam = symbols.define(
            kind: .valueParameter,
            name: interner.intern("x"),
            fqName: [interner.intern("test"), interner.intern("applyBlock"), interner.intern("x")],
            declSite: nil,
            visibility: .private
        )
        let inlineBlockParam = symbols.define(
            kind: .valueParameter,
            name: interner.intern("block"),
            fqName: [interner.intern("test"), interner.intern("applyBlock"), interner.intern("block")],
            declSite: nil,
            visibility: .private
        )
        let lambdaSymbol = symbols.define(
            kind: .function,
            name: interner.intern("$lambda_0"),
            fqName: [interner.intern("test"), interner.intern("$lambda_0")],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let lambdaParamSymbol = symbols.define(
            kind: .valueParameter,
            name: interner.intern("it"),
            fqName: [interner.intern("test"), interner.intern("$lambda_0"), interner.intern("it")],
            declSite: nil,
            visibility: .private
        )

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, funcType],
                returnType: intType,
                valueParameterSymbols: [inlineValueParam, inlineBlockParam]
            ),
            for: inlineSymbol
        )

        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: diagnostics
        )

        // Lambda function: { it -> it + 10 }
        let lambdaArgExpr = arena.appendExpr(.symbolRef(lambdaParamSymbol), type: intType)
        let lambdaTenExpr = arena.appendExpr(.intLiteral(10), type: intType)
        let lambdaSumExpr = arena.appendExpr(.temporary(100), type: intType)

        let lambdaFunction = KIRFunction(
            symbol: lambdaSymbol,
            name: interner.intern("$lambda_0"),
            params: [KIRParameter(symbol: lambdaParamSymbol, type: intType)],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: lambdaArgExpr, value: .symbolRef(lambdaParamSymbol)),
                .constValue(result: lambdaTenExpr, value: .intLiteral(10)),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_op_add"),
                    arguments: [lambdaArgExpr, lambdaTenExpr],
                    result: lambdaSumExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(lambdaSumExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        // Inline function: inline fun applyBlock(x: Int, block: (Int) -> Int): Int = block(x)
        let inlineXExpr = arena.appendExpr(.symbolRef(inlineValueParam), type: intType)
        let inlineBlockExpr = arena.appendExpr(.symbolRef(inlineBlockParam), type: funcType)
        let inlineCallResult = arena.appendExpr(.temporary(200), type: intType)

        let inlineFunction = KIRFunction(
            symbol: inlineSymbol,
            name: interner.intern("applyBlock"),
            params: [
                KIRParameter(symbol: inlineValueParam, type: intType),
                KIRParameter(symbol: inlineBlockParam, type: funcType),
            ],
            returnType: intType,
            body: [
                .constValue(result: inlineXExpr, value: .symbolRef(inlineValueParam)),
                .constValue(result: inlineBlockExpr, value: .symbolRef(inlineBlockParam)),
                .call(
                    symbol: inlineBlockParam,
                    callee: interner.intern("$lambda_0"),
                    arguments: [inlineXExpr],
                    result: inlineCallResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(inlineCallResult),
            ],
            isSuspend: false,
            isInline: true
        )

        // Caller: fun main(): Int = applyBlock(5) { it + 10 }
        let callerFiveExpr = arena.appendExpr(.intLiteral(5), type: intType)
        let callerLambdaRef = arena.appendExpr(.symbolRef(lambdaSymbol), type: funcType)
        let callerResult = arena.appendExpr(.temporary(300), type: intType)

        let mainFunction = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: callerFiveExpr, value: .intLiteral(5)),
                .constValue(result: callerLambdaRef, value: .symbolRef(lambdaSymbol)),
                .call(
                    symbol: inlineSymbol,
                    callee: interner.intern("applyBlock"),
                    arguments: [callerFiveExpr, callerLambdaRef],
                    result: callerResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callerResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let mainDeclID = arena.appendDecl(.function(mainFunction))
        _ = arena.appendDecl(.function(inlineFunction))
        _ = arena.appendDecl(.function(lambdaFunction))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainDeclID])],
            arena: arena
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "InlineLambda",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        guard case let .function(loweredMain)? = module.arena.decl(mainDeclID) else {
            XCTFail("Expected lowered main function")
            return
        }

        let callees = extractCallees(from: loweredMain.body, interner: interner)

        // The inline function call should be eliminated.
        XCTAssertFalse(
            callees.contains("applyBlock"),
            "applyBlock should have been inlined, got callees: \(callees)"
        )

        // The lambda indirect call should also be eliminated; instead the
        // lambda body (kk_op_add) should appear directly.
        XCTAssertFalse(
            callees.contains("$lambda_0"),
            "Lambda should have been inlined, got callees: \(callees)"
        )
        XCTAssertFalse(
            callees.contains("kk_lambda_invoke"),
            "Should not have indirect lambda invoke, got callees: \(callees)"
        )
        XCTAssertTrue(
            callees.contains("kk_op_add"),
            "Lambda body should be inlined with kk_op_add, got callees: \(callees)"
        )
    }

    /// Verify that non-lambda arguments (e.g. function references that are not
    /// resolved to a KIR function) still produce a regular call instruction.
    func testInlineLoweringFallsBackWhenLambdaNotResolvable() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let diagnostics = DiagnosticEngine()

        let intType = types.make(.primitive(.int, .nonNull))
        let funcType = types.make(.functionType(FunctionType(
            params: [intType],
            returnType: intType
        )))

        let mainSymbol = symbols.define(
            kind: .function,
            name: interner.intern("main"),
            fqName: [interner.intern("test"), interner.intern("main")],
            declSite: nil,
            visibility: .public
        )
        let inlineSymbol = symbols.define(
            kind: .function,
            name: interner.intern("applyBlock"),
            fqName: [interner.intern("test"), interner.intern("applyBlock")],
            declSite: nil,
            visibility: .public,
            flags: [.inlineFunction]
        )
        let inlineValueParam = symbols.define(
            kind: .valueParameter,
            name: interner.intern("x"),
            fqName: [interner.intern("test"), interner.intern("applyBlock"), interner.intern("x")],
            declSite: nil,
            visibility: .private
        )
        let inlineBlockParam = symbols.define(
            kind: .valueParameter,
            name: interner.intern("block"),
            fqName: [interner.intern("test"), interner.intern("applyBlock"), interner.intern("block")],
            declSite: nil,
            visibility: .private
        )
        // Use a symbol that does NOT exist as a KIR function declaration.
        let unknownFuncSymbol = symbols.define(
            kind: .function,
            name: interner.intern("externalFunc"),
            fqName: [interner.intern("test"), interner.intern("externalFunc")],
            declSite: nil,
            visibility: .public
        )

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, funcType],
                returnType: intType,
                valueParameterSymbols: [inlineValueParam, inlineBlockParam]
            ),
            for: inlineSymbol
        )

        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: diagnostics
        )

        // Inline function body: block(x)
        let inlineXExpr = arena.appendExpr(.symbolRef(inlineValueParam), type: intType)
        let inlineBlockExpr = arena.appendExpr(.symbolRef(inlineBlockParam), type: funcType)
        let inlineCallResult = arena.appendExpr(.temporary(0), type: intType)

        let inlineFunction = KIRFunction(
            symbol: inlineSymbol,
            name: interner.intern("applyBlock"),
            params: [
                KIRParameter(symbol: inlineValueParam, type: intType),
                KIRParameter(symbol: inlineBlockParam, type: funcType),
            ],
            returnType: intType,
            body: [
                .constValue(result: inlineXExpr, value: .symbolRef(inlineValueParam)),
                .constValue(result: inlineBlockExpr, value: .symbolRef(inlineBlockParam)),
                .call(
                    symbol: inlineBlockParam,
                    callee: interner.intern("externalFunc"),
                    arguments: [inlineXExpr],
                    result: inlineCallResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(inlineCallResult),
            ],
            isSuspend: false,
            isInline: true
        )

        // Caller passes a non-lambda symbolRef (not in module declarations).
        let callerArg = arena.appendExpr(.intLiteral(42), type: intType)
        let callerFuncRef = arena.appendExpr(.symbolRef(unknownFuncSymbol), type: funcType)
        let callerResult = arena.appendExpr(.temporary(1), type: intType)

        let mainFunction = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: callerArg, value: .intLiteral(42)),
                .constValue(result: callerFuncRef, value: .symbolRef(unknownFuncSymbol)),
                .call(
                    symbol: inlineSymbol,
                    callee: interner.intern("applyBlock"),
                    arguments: [callerArg, callerFuncRef],
                    result: callerResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callerResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let mainDeclID = arena.appendDecl(.function(mainFunction))
        _ = arena.appendDecl(.function(inlineFunction))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainDeclID])],
            arena: arena
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "InlineLambdaFallback",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        guard case let .function(loweredMain)? = module.arena.decl(mainDeclID) else {
            XCTFail("Expected lowered main function")
            return
        }

        let callees = extractCallees(from: loweredMain.body, interner: interner)

        // applyBlock should still be inlined (function body expansion).
        XCTAssertFalse(
            callees.contains("applyBlock"),
            "Inline function body should still be expanded"
        )

        // But the lambda call should remain as is since we cannot resolve
        // the function reference to a KIR declaration.
        XCTAssertTrue(
            callees.contains("externalFunc"),
            "Unresolvable callable should remain as indirect call, got callees: \(callees)"
        )
    }

    /// Verify that a multi-instruction lambda body is fully inlined (not just
    /// single-expression lambdas).
    func testInlineLoweringInlinesMultiStatementLambdaBody() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let diagnostics = DiagnosticEngine()

        let intType = types.make(.primitive(.int, .nonNull))
        let funcType = types.make(.functionType(FunctionType(
            params: [intType],
            returnType: intType
        )))

        let mainSymbol = symbols.define(
            kind: .function,
            name: interner.intern("main"),
            fqName: [interner.intern("test"), interner.intern("main")],
            declSite: nil,
            visibility: .public
        )
        let inlineSymbol = symbols.define(
            kind: .function,
            name: interner.intern("transform"),
            fqName: [interner.intern("test"), interner.intern("transform")],
            declSite: nil,
            visibility: .public,
            flags: [.inlineFunction]
        )
        let inlineValueParam = symbols.define(
            kind: .valueParameter,
            name: interner.intern("x"),
            fqName: [interner.intern("test"), interner.intern("transform"), interner.intern("x")],
            declSite: nil,
            visibility: .private
        )
        let inlineBlockParam = symbols.define(
            kind: .valueParameter,
            name: interner.intern("block"),
            fqName: [interner.intern("test"), interner.intern("transform"), interner.intern("block")],
            declSite: nil,
            visibility: .private
        )
        let lambdaSymbol = symbols.define(
            kind: .function,
            name: interner.intern("$lambda_1"),
            fqName: [interner.intern("test"), interner.intern("$lambda_1")],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let lambdaParamSymbol = symbols.define(
            kind: .valueParameter,
            name: interner.intern("n"),
            fqName: [interner.intern("test"), interner.intern("$lambda_1"), interner.intern("n")],
            declSite: nil,
            visibility: .private
        )

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, funcType],
                returnType: intType,
                valueParameterSymbols: [inlineValueParam, inlineBlockParam]
            ),
            for: inlineSymbol
        )

        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: diagnostics
        )

        // Lambda: { n -> val doubled = n * 2; doubled + 1 }
        let lambdaArgExpr = arena.appendExpr(.symbolRef(lambdaParamSymbol), type: intType)
        let lambdaTwoExpr = arena.appendExpr(.intLiteral(2), type: intType)
        let lambdaDoubledExpr = arena.appendExpr(.temporary(50), type: intType)
        let lambdaOneExpr = arena.appendExpr(.intLiteral(1), type: intType)
        let lambdaResultExpr = arena.appendExpr(.temporary(51), type: intType)

        let lambdaFunction = KIRFunction(
            symbol: lambdaSymbol,
            name: interner.intern("$lambda_1"),
            params: [KIRParameter(symbol: lambdaParamSymbol, type: intType)],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: lambdaArgExpr, value: .symbolRef(lambdaParamSymbol)),
                .constValue(result: lambdaTwoExpr, value: .intLiteral(2)),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_op_mul"),
                    arguments: [lambdaArgExpr, lambdaTwoExpr],
                    result: lambdaDoubledExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .constValue(result: lambdaOneExpr, value: .intLiteral(1)),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_op_add"),
                    arguments: [lambdaDoubledExpr, lambdaOneExpr],
                    result: lambdaResultExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(lambdaResultExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        // Inline: inline fun transform(x: Int, block: (Int) -> Int): Int = block(x)
        let inlineXExpr = arena.appendExpr(.symbolRef(inlineValueParam), type: intType)
        let inlineBlockExpr = arena.appendExpr(.symbolRef(inlineBlockParam), type: funcType)
        let inlineCallResult = arena.appendExpr(.temporary(60), type: intType)

        let inlineFunction = KIRFunction(
            symbol: inlineSymbol,
            name: interner.intern("transform"),
            params: [
                KIRParameter(symbol: inlineValueParam, type: intType),
                KIRParameter(symbol: inlineBlockParam, type: funcType),
            ],
            returnType: intType,
            body: [
                .constValue(result: inlineXExpr, value: .symbolRef(inlineValueParam)),
                .constValue(result: inlineBlockExpr, value: .symbolRef(inlineBlockParam)),
                .call(
                    symbol: inlineBlockParam,
                    callee: interner.intern("$lambda_1"),
                    arguments: [inlineXExpr],
                    result: inlineCallResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(inlineCallResult),
            ],
            isSuspend: false,
            isInline: true
        )

        // Caller
        let callerArgExpr = arena.appendExpr(.intLiteral(7), type: intType)
        let callerLambdaRef = arena.appendExpr(.symbolRef(lambdaSymbol), type: funcType)
        let callerResult = arena.appendExpr(.temporary(70), type: intType)

        let mainFunction = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: callerArgExpr, value: .intLiteral(7)),
                .constValue(result: callerLambdaRef, value: .symbolRef(lambdaSymbol)),
                .call(
                    symbol: inlineSymbol,
                    callee: interner.intern("transform"),
                    arguments: [callerArgExpr, callerLambdaRef],
                    result: callerResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callerResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let mainDeclID = arena.appendDecl(.function(mainFunction))
        _ = arena.appendDecl(.function(inlineFunction))
        _ = arena.appendDecl(.function(lambdaFunction))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainDeclID])],
            arena: arena
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "InlineMultiLambda",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        guard case let .function(loweredMain)? = module.arena.decl(mainDeclID) else {
            XCTFail("Expected lowered main function")
            return
        }

        let callees = extractCallees(from: loweredMain.body, interner: interner)

        // Both the inline function and the lambda should be inlined.
        XCTAssertFalse(callees.contains("transform"))
        XCTAssertFalse(callees.contains("$lambda_1"))
        // Both operations from the lambda body should appear.
        XCTAssertTrue(
            callees.contains("kk_op_mul"),
            "Lambda mul operation should be inlined, got: \(callees)"
        )
        XCTAssertTrue(
            callees.contains("kk_op_add"),
            "Lambda add operation should be inlined, got: \(callees)"
        )
    }
}
