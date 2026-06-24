#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - BuildAST BodyParsing Regression Tests

// Target: BuildASTPhase+BodyParsing.swift (56.9%)

@Suite
struct BuildASTBodyParsingRegressionTests {
    // MARK: - Typed local variable declaration

    @Test
    func testTypedLocalVariableDeclaration() throws {
        let source = """
        fun main(): Int {
            val x: Int = 42
            var y: String = "hello"
            val z: Boolean = true
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try #require(ctx.ast)
            #expect(ast.declarationCount >= 1)
        }
    }

    // MARK: - Local variable without initializer

    @Test
    func testLocalVariableWithoutInitializer() throws {
        let source = """
        fun main(): Int {
            var x: Int
            x = 5
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try #require(ctx.ast)
            #expect(ast.declarationCount >= 1)
        }
    }

    // MARK: - Local function with expression body

    @Test
    func testLocalFunctionWithExpressionBody() throws {
        let source = """
        fun outer(): Int {
            fun add(a: Int, b: Int) = a + b
            return add(1, 2)
        }
        fun main() = outer()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            #expect(!(sema.bindings.exprTypes.isEmpty))
        }
    }

    // MARK: - Nested local function

    @Test
    func testNestedLocalFunction() throws {
        let source = """
        fun outer(): Int {
            fun inner(): Int {
                fun deep(): Int = 42
                return deep()
            }
            return inner()
        }
        fun main() = outer()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            #expect(!(sema.bindings.exprTypes.isEmpty))
        }
    }

    @Test
    func testSuspendLocalFunctionParsesThroughKIR() throws {
        let source = """
        suspend fun delayed(value: Int): Int = value

        fun outer(): Int {
            suspend fun local(value: Int): Int = delayed(value)
            return 1
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            #expect(!(sema.bindings.exprTypes.isEmpty))
        }
    }

    // MARK: - Compound assignment operators in body parsing

    @Test
    func testCompoundAssignmentOperatorsInBody() throws {
        let source = """
        fun main(): Int {
            var x = 10
            x += 5
            x -= 3
            x *= 2
            x /= 4
            x %= 3
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try #require(ctx.ast)
            #expect(ast.declarationCount >= 1)
        }
    }

    // MARK: - Array assignment

    @Test
    func testArrayAssignmentInBody() throws {
        let source = """
        fun main(): Int {
            val arr = IntArray(5)
            arr[0] = 42
            arr[1] = 99
            return arr[0]
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try #require(ctx.ast)
            #expect(ast.declarationCount >= 1)
        }
    }

    // MARK: - Block body with multiple statements

    @Test
    func testBlockBodyMultipleStatements() throws {
        let source = """
        fun compute(a: Int, b: Int): Int {
            val sum = a + b
            val diff = a - b
            val product = sum * diff
            return product
        }
        fun main() = compute(5, 3)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)
            #expect(!(body.isEmpty))
        }
    }

    // MARK: - String template in body

    @Test
    func testStringTemplateInBody() throws {
        let source = """
        fun greet(name: String): String {
            val greeting = "Hello, $name!"
            return greeting
        }
        fun main() = greet("World")
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            #expect(!(sema.bindings.exprTypes.isEmpty))
        }
    }

    @Test
    func testAnnotatedExtensionFunctionTypeAliasPreservesTypeAnnotations() throws {
        let source = """
        annotation class A
        annotation class B
        typealias Action = @A @B @ExtensionFunctionType Function1<String, Unit>
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            // Skip bundled stdlib file — user file is last
            let file = try #require(ast.files.last)
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
            #expect(!(nullable))
        }
    }

    // MARK: - Lambda/Object literal/Callable reference roundtrip

    @Test
    func testLambdaObjectLiteralAndCallableReferenceRoundtripToASTLocals() throws {
        let source = """
        fun host(receiver: String): Int {
            val lambda = { value: Int -> value + 1 }
            val instance = object {
                fun size(): Int = 1
            }
            val ref = receiver::length
            return lambda(41)
        }

        fun after(): Int = 7
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            let funDecls = ast.arena.declarations().compactMap { decl -> FunDecl? in
                guard case let .funDecl(funDecl) = decl else {
                    return nil
                }
                return funDecl
            }
            let funNames = Set(funDecls.map { ctx.interner.resolve($0.name) })
            #expect(funNames.contains("host"))
            #expect(funNames.contains("after"))

            let hostDecl = try #require(funDecls.first(where: { ctx.interner.resolve($0.name) == "host" }))
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
                return (ctx.interner.resolve(name), initializer)
            }
            let localsByName = Dictionary(uniqueKeysWithValues: localInitializers.map { ($0.0, $0.1) })

            let lambdaInit = try #require(localsByName["lambda"])
            guard let lambdaExpr = ast.arena.expr(lambdaInit),
                  case .lambdaLiteral = lambdaExpr
            else {
                Issue.record("Expected `lambda` local initializer to be `.lambdaLiteral`.")
                return
            }

            let objectInit = try #require(localsByName["instance"])
            guard let objectExpr = ast.arena.expr(objectInit),
                  case .objectLiteral = objectExpr
            else {
                Issue.record("Expected `instance` local initializer to be `.objectLiteral`.")
                return
            }

            let callableInit = try #require(localsByName["ref"])
            guard let callableExpr = ast.arena.expr(callableInit),
                  case .callableRef = callableExpr
            else {
                Issue.record("Expected `ref` local initializer to be `.callableRef`.")
                return
            }
        }
    }

    // MARK: - Multi-line expression merging (BuildASTPhase+BodyParsing fix)

    @Test
    func testMultiLineFunctionCallMergesIntoSingleStatement() throws {
        // Arguments spread across multiple lines should be parsed as one call.
        let source = """
        fun add(a: Int, b: Int, c: Int): Int = a + b + c
        fun main(): Int {
            val result = add(
                1,
                2,
                3)
            return result
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })), "Expected no errors for multi-line call, got: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testMultiLineBinaryExpressionMergesIntoSingleStatement() throws {
        // A binary expression split across lines should merge when the previous
        // line ends with the operator.
        let source = """
        fun main(): Int {
            val x = 1 +
                2 +
                3
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })), "Expected no errors for multi-line binary expr, got: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testMultiLineStringConcatMergesCorrectly() throws {
        let source = """
        fun main(): String {
            val s = "Hello" +
                ", " +
                "World"
            return s
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })), "Expected no errors for multi-line string concat, got: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testChainedMemberCallsAcrossLinesMerge() throws {
        // Method chains split across lines (dot at start of next line) should parse correctly.
        let source = """
        fun main(): String {
            val s = "  hello  "
                .trim()
                .uppercase()
            return s
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })), "Expected no errors for chained member calls, got: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testClosingParenOnSeparateLineMergesWithCall() throws {
        // Closing paren on its own line should still be merged with the call.
        let source = """
        fun pair(a: Int, b: Int): Int = a + b
        fun main(): Int {
            val x = pair(
                10,
                20
            )
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })), "Expected no errors for closing paren on separate line, got: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testTopLevelDeclarationAnnotationsAreCollectedWithMixedModifierOrder() throws {
        let source = """
        package anno.ast

        public @Suppress("UNCHECKED_CAST")
        fun suppressedCast(x: Any): String = x as String
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            // Skip bundled stdlib file — user file is last
            let file = try #require(ast.sortedFiles.last)
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
    }

    @Test
    func testCompanionMemberAnnotationsAreCollectedWithMixedModifierOrder() throws {
        let source = """
        package anno.ast

        class Host {
            companion object {
                public @JvmStatic
                fun create(): Int = 1
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            // Skip bundled stdlib file — user file is last
            let file = try #require(ast.sortedFiles.last)
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
    }
}
#endif
