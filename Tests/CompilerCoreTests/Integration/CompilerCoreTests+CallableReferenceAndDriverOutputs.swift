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
            !ctx.diagnostics.hasError,
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
            file.packageFQName == [ctx.interner.intern("app")]
        }))
        let aliasedImport = try #require(appFile.imports.first(where: { importDecl in
            importDecl.alias != nil
        }))
        #expect(aliasedImport.alias == ctx.interner.intern("h"))
        #expect(aliasedImport.path == ["lib", "helper"].map(ctx.interner.intern))
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
            file.packageFQName == [ctx.interner.intern("app")]
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
        let addCallExprID = try #require(
            nameRefCallExprID(named: "add", in: ast, interner: ctx.interner)
        )

        let lambdaType = try #require(sema.bindings.exprTypes[lambdaExprID])
        let intType = sema.types.make(.primitive(.int, .nonNull))
        guard case let .functionType(functionType) = sema.types.kind(of: lambdaType) else {
            Issue.record("Lambda should infer function type.")
            return
        }
        #expect(functionType.params == [intType])
        #expect(functionType.returnType == intType)

        let offsetSymbol = try #require(sema.symbols.lookupByShortName(ctx.interner.intern("offset"))
            .compactMap(sema.symbols.symbol).first(where: { symbol in
            symbol.kind == .local
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
        let refCallExprID = try #require(
            nameRefCallExprID(named: "ref", in: ast, interner: ctx.interner)
        )
        let targetSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("target")]))
        #expect(sema.symbols.symbol(targetSymbol)?.kind == .function)

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
        let extensionSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("incByOne")]))
        #expect(sema.symbols.symbol(extensionSymbol)?.kind == .function)
        let capturedSymbols = try #require(sema.bindings.captureSymbolsByExpr[callableRefExprID])
        #expect(capturedSymbols.count == 1)
        let hostSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("host")]))
        let hostSignature = try #require(sema.symbols.functionSignature(for: hostSymbol))
        let seedSymbol = try #require(hostSignature.valueParameterSymbols.first)
        #expect(sema.symbols.symbol(seedSymbol)?.kind == .valueParameter)
        #expect(capturedSymbols == [seedSymbol])

        #expect(sema.bindings.callableTargets[callableRefExprID] == .symbol(extensionSymbol))
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
        let intOverloadSymbol = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("target")])
            .compactMap(sema.symbols.symbol).first(where: { symbol in
            guard symbol.kind == .function,
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
        let intOverloadSymbol = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("target")])
            .compactMap(sema.symbols.symbol).first(where: { symbol in
            guard symbol.kind == .function,
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
        let callExprID = try #require(
            nameRefCallExprID(named: "f", in: ast, interner: ctx.interner)
        )
        let callableCallBinding = try #require(sema.bindings.callableValueCalls[callExprID])
        guard case let .localValue(fParamSymbol) = callableCallBinding.target else {
            Issue.record("Callable value call should target the function-typed parameter f.")
            return
        }
        let fParam = try #require(sema.symbols.symbol(fParamSymbol))
        #expect(fParam.kind == .valueParameter)
        let apply = try #require(topLevelFunction(named: "apply", in: ast, interner: ctx.interner))
        #expect(fParam.name == apply.valueParams.first?.name)
        #expect(callableCallBinding.parameterMapping == [0: 0])

        let intType = sema.types.make(.primitive(.int, .nonNull))
        guard case let .functionType(functionType) = sema.types.kind(of: callableCallBinding.functionType) else {
            Issue.record("Callable value call binding should store function type.")
            return
        }
        #expect(functionType.params == [intType])
        #expect(functionType.returnType == intType)
    }

    /// KSP-496 follow-up: a property callable reference with no expected type
    /// used to fall back to the property's own value type (`Int` here), which
    /// silently broke `is KProperty<*>` checks and printed the reference as
    /// its value type's default instead of a real `KProperty0`. See
    /// `Tests/CompilerCoreTests/Sema/PropertyCallableReferenceDefaultTypeTests.swift`
    /// for the full coverage of this fix; this test just keeps pinning the
    /// symbol binding for `::answer` while asserting the corrected type.
    @Test func testPropertyCallableReferenceInfersKProperty0ForFallbackBinding() throws {
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
        let answerSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("answer")]))
        #expect(sema.symbols.symbol(answerSymbol)?.kind == .property)

        #expect(sema.bindings.identifierSymbols[callableRefExprID] == answerSymbol)

        let exprType = try #require(sema.bindings.exprTypes[callableRefExprID])
        guard case let .classType(classType) = sema.types.kind(of: exprType) else {
            Issue.record("Expected ::answer to infer a class type (KProperty0<Int>), got \(sema.types.kind(of: exprType))")
            return
        }
        let propertyClass = try #require(sema.symbols.lookup(fqName: ["kotlin", "reflect", "KProperty0"].map(ctx.interner.intern)))
        #expect(
            classType.classSymbol == propertyClass,
            "::answer without an expected type should infer KProperty0<Int>"
        )
    }

    /// REFL-CTOR: a bare `::Foo` where `Foo` names a class introduces an
    /// unbound *constructor* reference `(Args...) -> Foo`. Constructors are
    /// stored under `<init>`, not `Foo`, so the ordinary `.function ||
    /// .constructor` scope lookup for `member` never finds them without the
    /// dedicated class-lookup fallback this pins.
    @Test func testBareConstructorReferenceInfersFunctionTypeAndBindsConstructorSymbol() throws {
        let source = """
        class Foo(val n: Int)
        fun use(): Foo {
            val ctor = ::Foo
            return ctor(3)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let classSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Foo")]))
        let ctorSymbol = try #require(sema.symbols.children(ofFQName: [ctx.interner.intern("Foo")])
            .compactMap(sema.symbols.symbol).first(where: { symbol in
            symbol.kind == .constructor
                && sema.symbols.parentSymbol(for: symbol.id) == classSymbol
        })?.id)

        #expect(sema.bindings.identifierSymbols[callableRefExprID] == ctorSymbol)
        #expect(sema.bindings.callableTargets[callableRefExprID] == .symbol(ctorSymbol))

        let refType = try #require(sema.bindings.exprTypes[callableRefExprID])
        let intType = sema.types.make(.primitive(.int, .nonNull))
        guard case let .functionType(functionType) = sema.types.kind(of: refType) else {
            Issue.record("Constructor reference should infer function type.")
            return
        }
        #expect(functionType.params == [intType])
        guard case let .classType(returnClassType) = sema.types.kind(of: functionType.returnType) else {
            Issue.record("Constructor reference should return the class type.")
            return
        }
        #expect(returnClassType.classSymbol == classSymbol)
    }

    /// KUU-917: a class used as the receiver of a nested constructor reference
    /// provides the constructor's owner, not a captured receiver argument.
    @Test func testNestedConstructorReferenceBindsConstructorWithoutReceiver() throws {
        let source = """
        class Outer { class Nested(val n: Int) }
        fun make(): Outer.Nested {
            val ctor: (Int) -> Outer.Nested = Outer::Nested
            return ctor(7)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let ref = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let ctor = try #require(sema.bindings.identifierSymbols[ref])
        #expect(sema.symbols.symbol(ctor)?.kind == .constructor)
        #expect(!sema.bindings.isUnboundCallableRef(ref))
        let type = try #require(sema.bindings.exprTypes[ref])
        guard case let .functionType(function) = sema.types.kind(of: type) else {
            Issue.record("Expected nested constructor function type.")
            return
        }
        #expect(function.params == [sema.types.make(.primitive(.int, .nonNull))])
        guard case let .classType(result) = sema.types.kind(of: function.returnType) else {
            Issue.record("Expected nested constructor result type.")
            return
        }
        let nestedClass = try #require(sema.symbols.lookup(fqName: ["Outer", "Nested"].map(ctx.interner.intern)))
        #expect(result.classSymbol == nestedClass)
        #expect(sema.symbols.parentSymbol(for: ctor) == nestedClass)
    }

    /// KUU-917: a bare reference in an extension body binds its receiver,
    /// including members inherited through an interface.
    @Test func testExtensionBareMemberReferenceBindsImplicitReceiver() throws {
        let source = """
        interface Writer { fun flush(): Int }
        fun flush(): Int = 7
        fun Writer.flushLater(): () -> Int = ::flush
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let ref = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        #expect(sema.bindings.implicitReceiverMemberNames[ref] != nil)
        let member = try #require(sema.bindings.identifierSymbols[ref])
        let owner = try #require(sema.symbols.parentSymbol(for: member))
        #expect(sema.symbols.symbol(owner)?.kind == .interface)
        let type = try #require(sema.bindings.exprTypes[ref])
        guard case let .functionType(function) = sema.types.kind(of: type) else {
            Issue.record("Expected bound member function type.")
            return
        }
        #expect(function.params.isEmpty)
        #expect(function.returnType == sema.types.make(.primitive(.int, .nonNull)))
    }

    @Test func testSuspendImplicitMemberReferenceRetainsSuspendFunctionType() throws {
        let source = """
        interface Writer { suspend fun flush(): Int }
        fun Writer.flushLater(): suspend () -> Int = ::flush
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let ref = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let type = try #require(sema.bindings.exprTypes[ref])
        guard case let .functionType(function) = sema.types.kind(of: type) else {
            Issue.record("Expected suspend function reference type.")
            return
        }
        #expect(function.isSuspend)
        #expect(function.params.isEmpty)
    }

    @Test func testImplicitMemberReferenceBeatsSameNamedPackageProperty() throws {
        let source = """
        interface Writer { fun flush(): Int }
        val flush: Int = 7
        fun Writer.flushLater(): () -> Int = ::flush
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let ref = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let member = try #require(sema.bindings.identifierSymbols[ref])
        let owner = try #require(sema.symbols.parentSymbol(for: member))
        #expect(sema.symbols.symbol(owner)?.kind == .interface)
        #expect(sema.bindings.implicitReceiverMemberNames[ref] != nil)
    }

    /// The implicit-receiver fallback must leave a top-level `::function`
    /// unchanged, even when that reference occurs inside an extension body.
    @Test func testTopLevelCallableReferenceInsideExtensionRemainsReceiverless() throws {
        let source = """
        interface Writer { fun flush(): Int }
        fun top(): Int = 3
        fun Writer.topLater(): () -> Int = ::top
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let ref = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        #expect(sema.bindings.implicitReceiverMemberNames[ref] == nil)
        let type = try #require(sema.bindings.exprTypes[ref])
        guard case let .functionType(function) = sema.types.kind(of: type) else {
            Issue.record("Expected top-level function reference type.")
            return
        }
        #expect(function.params.isEmpty)
    }

    /// REFL-EXTPROP: `String::length` is a package-level extension property
    /// (`Sources/CompilerCore/Stdlib/kotlin/String.kt`) registered under its
    /// declaring package's FQ name, not under `kotlin.String`'s -- the
    /// FQ-based owner-member lookup used for a class-owned property
    /// reference never finds it without the `extensionPropertyReceiverType`
    /// fallback this pins.
    @Test func testUnboundExtensionPropertyReferenceInfersFunctionType() throws {
        let source = """
        fun use(): (String) -> Int = String::length
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        #expect(sema.bindings.callableRefKind(for: callableRefExprID) == .propertyRef)
        #expect(sema.bindings.isUnboundCallableRef(callableRefExprID))

        let refType = try #require(sema.bindings.exprTypes[callableRefExprID])
        let intType = sema.types.make(.primitive(.int, .nonNull))
        guard case let .functionType(functionType) = sema.types.kind(of: refType) else {
            Issue.record("Extension property reference should infer function type.")
            return
        }
        #expect(functionType.params == [sema.types.stringType])
        #expect(functionType.returnType == intType)
    }

    /// REFL-PRIMOP: `Int::plus` / `Int::times` have no backing member
    /// symbol at all -- primitive arithmetic is a table-driven
    /// type-inference special case
    /// (`tryInferRegularMemberCallPrimitiveSpecials`), not a function
    /// declaration, so this exercises the dedicated
    /// `primitiveOperatorCallableRef` binding instead of the usual
    /// symbol-based `callableTargets`.
    @Test func testPrimitiveOperatorReferencesInferHomogeneousFunctionType() throws {
        let source = """
        fun usePlus(): (Int, Int) -> Int = Int::plus
        fun useTimes(): (Int, Int) -> Int = Int::times
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), case .callableRef = expr else { return nil }
            return exprID
        }
        #expect(callableRefExprIDs.count == 2)

        let intType = sema.types.make(.primitive(.int, .nonNull))
        let expectedOps: [BinaryOp] = [.add, .multiply]
        for (exprID, expectedOp) in zip(callableRefExprIDs, expectedOps) {
            #expect(sema.bindings.primitiveOperatorCallableRef(for: exprID) == expectedOp)
            let refType = try #require(sema.bindings.exprTypes[exprID])
            guard case let .functionType(functionType) = sema.types.kind(of: refType) else {
                Issue.record("Primitive operator reference should infer function type.")
                continue
            }
            #expect(functionType.params == [intType, intType])
            #expect(functionType.returnType == intType)
        }
    }

    @Test func testPrimitiveOperatorReferenceWithoutExpectedTypeIsAmbiguous() throws {
        let source = """
        fun main() {
            val plus = Int::plus
            println(plus(2, 3))
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0003", in: ctx)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let ref = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        #expect(sema.bindings.exprTypes[ref] == sema.types.errorType)
        #expect(sema.bindings.primitiveOperatorCallableRef(for: ref) == nil)
        #expect(sema.bindings.callableRefKind(for: ref) == nil)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0003"
                && $0.message.contains("Int::plus")
                && $0.primaryRange == ast.arena.exprRange(ref)
        })
    }

    @Test(arguments: ["", ": Any"])
    func testPrimitiveOperatorReferencesNeedFunctionExpectedType(annotation: String) throws {
        let receivers = ["Int", "Long", "UInt", "ULong", "Float", "Double"]
        let source = receivers.flatMap { receiver in
            ["plus", "times"].map { member in
                "val ref\(receiver)\(member)\(annotation) = \(receiver)::\(member)"
            }
        }.joined(separator: "\n")
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let refs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case .callableRef = ast.arena.expr(id) else { return nil }
            return id
        }
        #expect(refs.count == 12)
        #expect(ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0003" }.count == 12)
        for ref in refs {
            #expect(sema.bindings.exprTypes[ref] == sema.types.errorType)
            #expect(sema.bindings.primitiveOperatorCallableRef(for: ref) == nil)
        }
    }

    @Test func testPrimitiveOperatorReferencesWithExpectedTypesRemainValid() throws {
        let source = """
        fun accept(op: (Int, Int) -> Int): Int = op(2, 3)
        fun use(): Int {
            val plus: (Int, Int) -> Int = Int::plus
            val times: (Int, Int) -> Int = Int::times
            return accept(Int::plus) + accept(Int::times) + plus(2, 3) + times(2, 3)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let refs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case .callableRef = ast.arena.expr(id) else { return nil }
            return id
        }
        #expect(refs.count == 4)
        for (ref, op) in zip(refs, [BinaryOp.add, .multiply, .add, .multiply]) {
            #expect(sema.bindings.primitiveOperatorCallableRef(for: ref) == op)
        }
    }

    /// A bound reference to a method of a generic interface instantiation
    /// (`t::apply` with `t: Transformer<Int, Int>`) substitutes the receiver's
    /// type arguments into the member's signature instead of leaving the
    /// declared type parameters (`(A) -> B`) in the function type.
    @Test func testBoundGenericInterfaceMethodReferenceSubstitutesReceiverTypeArguments() throws {
        let source = """
        interface Transformer<A, B> { fun apply(a: A): B }
        fun use(t: Transformer<Int, Int>): (Int) -> Int = t::apply
        fun infer(t: Transformer<Int, String>) = t::apply
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let callableRefExprIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), case .callableRef = expr else { return nil }
            return exprID
        }
        #expect(callableRefExprIDs.count == 2)
        let inferredRef = try #require(callableRefExprIDs.last)
        let refType = try #require(sema.bindings.exprTypes[inferredRef])
        guard case let .functionType(functionType) = sema.types.kind(of: refType) else {
            Issue.record("Bound generic interface method reference should infer a function type.")
            return
        }
        #expect(functionType.params == [intType])
        #expect(functionType.returnType == sema.types.stringType)
    }

    /// `Int::toString` has no zero-argument member symbol (only
    /// `toString(radix)` is declared); with a one-parameter expected function
    /// type it resolves to a synthesized `(Int) -> String`, while a two-parameter
    /// expected type still picks the real `toString(radix)` overload.
    @Test func testOverloadedToStringReferenceIsChosenByExpectedFunctionArity() throws {
        let source = """
        fun one(): (Int) -> String = Int::toString
        fun two(): (Int, Int) -> String = Int::toString
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), case .callableRef = expr else { return nil }
            return exprID
        }
        #expect(callableRefExprIDs.count == 2)
        #expect(sema.bindings.isAnyToStringCallableRef(callableRefExprIDs[0]))
        #expect(!sema.bindings.isAnyToStringCallableRef(callableRefExprIDs[1]))
        #expect(sema.bindings.callableTarget(for: callableRefExprIDs[1]) != nil)
    }
}
#endif
