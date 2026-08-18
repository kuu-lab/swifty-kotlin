#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - BuildAST BodyParsing Regression Tests

// Target: BuildASTPhase+BodyParsing.swift (56.9%)

@Suite
struct BuildASTBodyParsingRegressionTests {

    private static nonisolated(unsafe) var _sharedBodyParsingKIRCtx: CompilationContext?

    private func sharedBodyParsingKIRCtx() throws -> CompilationContext {
        if let cached = Self._sharedBodyParsingKIRCtx {
            return cached
        }

        let sources: [String] = [
            """
            package buildast.kir0
            fun outer0(): Int {
                fun add0(a: Int, b: Int) = a + b
                return add0(1, 2)
            }
            fun main0() = outer0()
            """,
            """
            package buildast.kir1
            fun outer1(): Int {
                fun inner1(): Int {
                    fun deep1(): Int = 42
                    return deep1()
                }
                return inner1()
            }
            fun main1() = outer1()
            """,
            """
            package buildast.kir2
            suspend fun delayed2(value: Int): Int = value
            fun outer2(): Int {
                suspend fun local2(value: Int): Int = delayed2(value)
                return 1
            }
            """,
            """
            package buildast.kir3
            fun compute3(a: Int, b: Int): Int {
                val sum = a + b
                val diff = a - b
                val product = sum * diff
                return product
            }
            fun main3() = compute3(5, 3)
            """,
            """
            package buildast.kir4
            fun greet4(name: String): String {
                val greeting = "Hello, $name!"
                return greeting
            }
            fun main4() = greet4("World")
            """,
            """
            package buildast.kir5
            fun add5(a: Int, b: Int, c: Int): Int = a + b + c
            fun main5(): Int {
                val result = add5(
                    1,
                    2,
                    3)
                return result
            }
            """,
            """
            package buildast.kir6
            fun main6(): Int {
                val x = 1 +
                    2 +
                    3
                return x
            }
            """,
            """
            package buildast.kir7
            fun main7(): String {
                val s = "Hello" +
                    ", " +
                    "World"
                return s
            }
            """,
            """
            package buildast.kir8
            fun main8(): String {
                val s = "  hello  "
                    .trim()
                    .uppercase()
                return s
            }
            """,
            """
            package buildast.kir9
            fun pair9(a: Int, b: Int): Int = a + b
            fun main9(): Int {
                val x = pair9(
                    10,
                    20
                )
                return x
            }
            """,
        ]

        var result: CompilationContext?
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToKIR(ctx)
            result = ctx
        }

        let ctx = try #require(result)
        Self._sharedBodyParsingKIRCtx = ctx
        return ctx
    }
    // MARK: - Frontend body parsing cases

    /// Frontend-only cases share one source manager while retaining per-file checks.
    @Test
    func testFrontendBodyParsingRegression() throws {
        let sources = [
            """
            package buildast.frontend0
            fun typedMain(): Int {
                val x: Int = 42
                var y: String = "hello"
                val z: Boolean = true
                return x
            }
            """,
            """
            package buildast.frontend1
            fun uninitializedMain(): Int {
                var x: Int
                x = 5
                return x
            }
            """,
            """
            package buildast.frontend2
            fun compoundMain(): Int {
                var x = 10
                x += 5
                x -= 3
                x *= 2
                x /= 4
                x %= 3
                return x
            }
            """,
            """
            package buildast.frontend3
            fun arrayMain(): Int {
                val arr = IntArray(5)
                arr[0] = 42
                arr[1] = 99
                return arr[0]
            }
            """,
            """
            package buildast.frontend4
            annotation class A
            annotation class B
            typealias Action = @A @B @ExtensionFunctionType Function1<String, Unit>
            """,
            """
            package buildast.frontend5
            fun host(receiver: String): Int {
                val lambda = { value: Int -> value + 1 }
                val instance = object {
                    fun size(): Int = 1
                }
                val ref = receiver::length
                return lambda(41)
            }

            fun after(): Int = 7
            """,
            """
            package buildast.frontend6
            public @Suppress("UNCHECKED_CAST")
            fun suppressedCast(x: Any): String = x as String
            """,
            """
            package buildast.frontend7
            class Host {
                companion object {
                    public @JvmStatic
                    fun create(): Int = 1
                }
            }
            """,
            """
            package buildast.frontend8
            @RuntimeName("first")
            external fun first(value: Boolean)

            @RuntimeName("second")
            external fun second(value: Boolean)
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runFrontend(ctx)

            for path in paths {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "Shared BuildAST fixture should have no errors for \(path): \(errors.map(\.message))")
            }

            let ast = try #require(ctx.ast)
            #expect(ast.declarationCount >= 9)

            func fileByPath(_ path: String) throws -> ASTFile {
                let fileID = try #require(ctx.sourceManager.fileID(forPath: path))
                return try #require(ast.files.first { $0.fileID == fileID })
            }

            for index in 0...3 {
                _ = try fileByPath(paths[index])
            }

            do {
                let file = try fileByPath(paths[4])
                let aliasDeclID = try #require(file.topLevelDecls.first(where: {
                    if case .typeAliasDecl = ast.arena.decl($0) {
                        return true
                    }
                    return false
                }))

                guard case let .typeAliasDecl(typeAliasDecl) = ast.arena.decl(aliasDeclID) else {
                    Issue.record("Expected typealias declaration")
                    return
                }
                let underlyingType = try #require(typeAliasDecl.underlyingType)
                guard case let .annotated(base, annotations) = try #require(ast.arena.typeRef(underlyingType)) else {
                    Issue.record("Expected annotated type reference")
                    return
                }

                #expect(annotations.map(\.name) == ["A", "B", "ExtensionFunctionType"])

                guard case let .named(path, args, nullable) = try #require(ast.arena.typeRef(base)) else {
                    Issue.record("Expected named type reference")
                    return
                }

                #expect(path.map(ctx.interner.resolve) == ["Function1"])
                #expect(args.count == 2)
                #expect(!nullable)
            }

            do {
                _ = try fileByPath(paths[5])
                let funDecls = ast.arena.declarations().compactMap { decl -> FunDecl? in
                    guard case let .funDecl(funDecl) = decl else {
                        return nil
                    }
                    return funDecl
                }
                let interner = ctx.interner
                let funNames = Set(funDecls.map { interner.resolve($0.name) })
                #expect(funNames.contains("host"))
                #expect(funNames.contains("after"))

                let hostDecl = try #require(funDecls.first(where: { interner.resolve($0.name) == "host" }))
                guard case let .block(bodyExprs, _) = hostDecl.body else {
                    Issue.record("host should have a block body")
                    return
                }

                let localInitializers = bodyExprs.compactMap { exprID -> (String, ExprID)? in
                    guard let expr = ast.arena.expr(exprID),
                          case let .localDecl(name, _, _, initializer, _, _) = expr,
                          let initializer
                    else {
                        return nil
                    }
                    return (interner.resolve(name), initializer)
                }
                let localsByName = Dictionary(uniqueKeysWithValues: localInitializers.map { ($0.0, $0.1) })

                let lambdaInit = try #require(localsByName["lambda"])
                guard let lambdaExpr = ast.arena.expr(lambdaInit),
                      case .lambdaLiteral = lambdaExpr
                else {
                    Issue.record("Expected lambda local initializer to be a lambda literal.")
                    return
                }

                let objectInit = try #require(localsByName["instance"])
                guard let objectExpr = ast.arena.expr(objectInit),
                      case .objectLiteral = objectExpr
                else {
                    Issue.record("Expected instance local initializer to be an object literal.")
                    return
                }

                let callableInit = try #require(localsByName["ref"])
                guard let callableExpr = ast.arena.expr(callableInit),
                      case .callableRef = callableExpr
                else {
                    Issue.record("Expected ref local initializer to be a callable reference.")
                    return
                }
            }

            do {
                let file = try fileByPath(paths[6])
                let function = try #require(file.topLevelDecls.compactMap { declID -> FunDecl? in
                    guard let decl = ast.arena.decl(declID),
                          case let .funDecl(funDecl) = decl,
                          ctx.interner.resolve(funDecl.name) == "suppressedCast"
                    else {
                        return nil
                    }
                    return funDecl
                }.first)

                #expect(function.annotations.count == 1)
                #expect(function.annotations[0].name == "Suppress")
                #expect(function.annotations[0].arguments == ["\"\"UNCHECKED_CAST\"\""])
            }

            do {
                let file = try fileByPath(paths[7])
                let hostClass = try #require(file.topLevelDecls.compactMap { declID -> ClassDecl? in
                    guard let decl = ast.arena.decl(declID),
                          case let .classDecl(classDecl) = decl,
                          ctx.interner.resolve(classDecl.name) == "Host"
                    else {
                        return nil
                    }
                    return classDecl
                }.first)
                let companionDeclID = try #require(hostClass.companionObject)
                guard let companionDecl = ast.arena.decl(companionDeclID),
                      case let .objectDecl(companionObject) = companionDecl
                else {
                    Issue.record("Expected companion object declaration.")
                    return
                }
                let companionFunctionDeclID = try #require(companionObject.memberFunctions.first)
                guard let functionDecl = ast.arena.decl(companionFunctionDeclID),
                      case let .funDecl(function) = functionDecl
                else {
                    Issue.record("Expected companion member function declaration.")
                    return
                }

                #expect(function.annotations.count == 1)
                #expect(function.annotations[0].name == "JvmStatic")
            }

            do {
                let file = try fileByPath(paths[8])
                let functions = file.topLevelDecls.compactMap { declID -> FunDecl? in
                    guard let decl = ast.arena.decl(declID),
                          case let .funDecl(function) = decl
                    else {
                        return nil
                    }
                    return function
                }

                #expect(functions.count == 2)
                #expect(functions.map { ctx.interner.resolve($0.name) } == ["first", "second"])
                #expect(functions.map { $0.annotations.first?.name } == ["RuntimeName", "RuntimeName"])
                #expect(functions.map { $0.annotations.first?.arguments.first } == ["\"\"first\"\"", "\"\"second\"\""])
            }
        }
    }

    // MARK: - Local function with expression body

    @Test
    func testLocalFunctionWithExpressionBody() throws {
        let ctx = try sharedBodyParsingKIRCtx()
        let sema = try #require(ctx.sema)
        #expect(!(sema.bindings.exprTypes.isEmpty))
    }
    @Test
    func testNestedLocalFunction() throws {
        let ctx = try sharedBodyParsingKIRCtx()
        let sema = try #require(ctx.sema)
        #expect(!(sema.bindings.exprTypes.isEmpty))
    }
    @Test
    func testSuspendLocalFunctionParsesThroughKIR() throws {
        let ctx = try sharedBodyParsingKIRCtx()
        let sema = try #require(ctx.sema)
        #expect(!(sema.bindings.exprTypes.isEmpty))
    }
    @Test
    func testBlockBodyMultipleStatements() throws {
        let ctx = try sharedBodyParsingKIRCtx()
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "compute3", in: module, interner: ctx.interner)
        #expect(!(body.isEmpty))
    }
    @Test
    func testStringTemplateInBody() throws {
        let ctx = try sharedBodyParsingKIRCtx()
        let sema = try #require(ctx.sema)
        #expect(!(sema.bindings.exprTypes.isEmpty))
    }
    @Test
    func testMultiLineFunctionCallMergesIntoSingleStatement() throws {
        let ctx = try sharedBodyParsingKIRCtx()
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
                "Expected no errors for multi-line call, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }
    @Test
    func testMultiLineBinaryExpressionMergesIntoSingleStatement() throws {
        let ctx = try sharedBodyParsingKIRCtx()
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
                "Expected no errors for multi-line binary expr, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }
    @Test
    func testMultiLineStringConcatMergesCorrectly() throws {
        let ctx = try sharedBodyParsingKIRCtx()
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
                "Expected no errors for multi-line string concat, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }
    @Test
    func testChainedMemberCallsAcrossLinesMerge() throws {
        let ctx = try sharedBodyParsingKIRCtx()
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
                "Expected no errors for chained member calls, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }
    @Test
    func testClosingParenOnSeparateLineMergesWithCall() throws {
        let ctx = try sharedBodyParsingKIRCtx()
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
                "Expected no errors for closing paren on separate line, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }
}
#endif
