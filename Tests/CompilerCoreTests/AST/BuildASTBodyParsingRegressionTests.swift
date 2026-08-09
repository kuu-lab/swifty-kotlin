#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - BuildAST BodyParsing Regression Tests

// Target: BuildASTPhase+BodyParsing.swift (56.9%)

@Suite
struct BuildASTBodyParsingRegressionTests {

    /// Body-parsing regression cases must parse through the full pipeline in
    /// a single compilation, with per-source AST checks isolated by file ID.
    @Test
    func testBuildASTBodyParsingRegression() throws {
        let sources: [String] = [
            // 0: typed local variable declaration
            """
            package sample0
            fun main0(): Int {
                val x: Int = 42
                var y: String = "hello"
                val z: Boolean = true
                return x
            }
            """,
            // 1: local variable without initializer
            """
            package sample1
            fun main1(): Int {
                var x: Int
                x = 5
                return x
            }
            """,
            // 2: local function with expression body
            """
            package sample2
            fun outer2(): Int {
                fun add2(a: Int, b: Int) = a + b
                return add2(1, 2)
            }
            fun main2() = outer2()
            """,
            // 3: nested local function
            """
            package sample3
            fun outer3(): Int {
                fun inner3(): Int {
                    fun deep3(): Int = 42
                    return deep3()
                }
                return inner3()
            }
            fun main3() = outer3()
            """,
            // 4: suspend local function parses through KIR
            """
            package sample4
            suspend fun delayed4(value: Int): Int = value

            fun outer4(): Int {
                suspend fun local4(value: Int): Int = delayed4(value)
                return 1
            }
            """,
            // 5: compound assignment operators
            """
            package sample5
            fun main5(): Int {
                var x = 10
                x += 5
                x -= 3
                x *= 2
                x /= 4
                x %= 3
                return x
            }
            """,
            // 6: array assignment
            """
            package sample6
            fun main6(): Int {
                val arr = IntArray(5)
                arr[0] = 42
                arr[1] = 99
                return arr[0]
            }
            """,
            // 7: block body with multiple statements
            """
            package sample7
            fun compute7(a: Int, b: Int): Int {
                val sum = a + b
                val diff = a - b
                val product = sum * diff
                return product
            }
            fun main7() = compute7(5, 3)
            """,
            // 8: string template in body
            """
            package sample8
            fun greet8(name: String): String {
                val greeting = "Hello, $name!"
                return greeting
            }
            fun main8() = greet8("World")
            """,
            // 9: annotated extension function type alias preserves annotations
            """
            package sample9
            annotation class A9
            annotation class B9
            typealias Action9 = @A9 @B9 @ExtensionFunctionType Function1<String, Unit>
            """,
            // 10: lambda / object literal / callable reference roundtrip
            """
            package sample10
            fun host(receiver: String): Int {
                val lambda = { value: Int -> value + 1 }
                val instance = object {
                    fun size(): Int = 1
                }
                val ref = receiver::length
                return lambda(41)
            }

            fun after() = 7
            """,
            // 11: multi-line function call merges into single statement
            """
            package sample11
            fun add11(a: Int, b: Int, c: Int): Int = a + b + c
            fun main11(): Int {
                val result = add11(
                    1,
                    2,
                    3)
                return result
            }
            """,
            // 12: multi-line binary expression merges into single statement
            """
            package sample12
            fun main12(): Int {
                val x = 1 +
                    2 +
                    3
                return x
            }
            """,
            // 13: multi-line string concat merges correctly
            """
            package sample13
            fun main13(): String {
                val s = "Hello" +
                    ", " +
                    "World"
                return s
            }
            """,
            // 14: chained member calls across lines merge
            """
            package sample14
            fun main14(): String {
                val s = "  hello  "
                    .trim()
                    .uppercase()
                return s
            }
            """,
            // 15: closing paren on separate line merges with call
            """
            package sample15
            fun pair15(a: Int, b: Int): Int = a + b
            fun main15(): Int {
                val x = pair15(
                    10,
                    20
                )
                return x
            }
            """,
            // 16: top-level declaration annotations with mixed modifier order
            """
            package sample16

            public @Suppress("UNCHECKED_CAST")
            fun suppressedCast16(x: Any): String = x as String
            """,
            // 17: companion member annotations with mixed modifier order
            """
            package sample17

            class Host17 {
                companion object {
                    public @JvmStatic
                    fun create(): Int = 1
                }
            }
            """,
            // 18: annotation after bodyless external function starts next declaration
            """
            package sample18

            @RuntimeName("first")
            external fun first18(value: Boolean)

            @RuntimeName("second")
            external fun second18(value: Boolean)
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToKIR(ctx)

            let ast = try #require(ctx.ast)
            let kir = try #require(ctx.kir)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            #expect(!ast.files.isEmpty)
            #expect(!(sema.bindings.exprTypes.isEmpty))

            for path in paths {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.message))")
            }

            func fileByPath(_ path: String) throws -> ASTFile {
                let fileID = try #require(ctx.sourceManager.fileID(forPath: path))
                return try #require(ast.files.first { $0.fileID == fileID })
            }

            // 0-1: AST has declarations
            do {
                _ = try fileByPath(paths[0])
                _ = try fileByPath(paths[1])
            }

            // 7: compute function body is not empty
            do {
                let body = try findKIRFunctionBody(named: "compute7", in: kir, interner: interner)
                #expect(!body.isEmpty)
            }

            // 9: typealias preserves annotations and named type reference
            do {
                let file = try fileByPath(paths[9])
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

                #expect(annotations.map(\.name) == ["A9", "B9", "ExtensionFunctionType"])

                guard case let .named(path, args, nullable) = try #require(ast.arena.typeRef(base)) else {
                    Issue.record("Expected named type reference")
                    return
                }

                #expect(path.map(interner.resolve) == ["Function1"])
                #expect(args.count == 2)
                #expect(!nullable)
            }

            // 10: lambda / object literal / callable reference roundtrip
            do {
                _ = try fileByPath(paths[10])
                let funDecls = ast.arena.declarations().compactMap { decl -> FunDecl? in
                    guard case let .funDecl(funDecl) = decl else { return nil }
                    return funDecl
                }
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

            // 16: top-level declaration annotations
            do {
                let file = try fileByPath(paths[16])
                let function = try #require(file.topLevelDecls.compactMap { declID -> FunDecl? in
                    guard let decl = ast.arena.decl(declID),
                          case let .funDecl(funDecl) = decl,
                          interner.resolve(funDecl.name) == "suppressedCast16"
                    else {
                        return nil
                    }
                    return funDecl
                }.first)

                #expect(function.annotations.count == 1)
                #expect(function.annotations[0].name == "Suppress")
                #expect(function.annotations[0].arguments == ["\"\"UNCHECKED_CAST\"\""])
            }

            // 17: companion member annotations
            do {
                let file = try fileByPath(paths[17])
                let hostClass = try #require(file.topLevelDecls.compactMap { declID -> ClassDecl? in
                    guard let decl = ast.arena.decl(declID),
                          case let .classDecl(classDecl) = decl,
                          interner.resolve(classDecl.name) == "Host17"
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

            // 18: annotation after bodyless external function
            do {
                let file = try fileByPath(paths[18])
                let functions = file.topLevelDecls.compactMap { declID -> FunDecl? in
                    guard let decl = ast.arena.decl(declID),
                          case let .funDecl(function) = decl
                    else {
                        return nil
                    }
                    return function
                }

                #expect(functions.count == 2)
                #expect(functions.map { interner.resolve($0.name) } == ["first18", "second18"])
                #expect(functions.map { $0.annotations.first?.name } == ["RuntimeName", "RuntimeName"])
                #expect(functions.map { $0.annotations.first?.arguments.first } == ["\"\"first\"\"", "\"\"second\"\""])
            }
        }
    }
}
#endif
