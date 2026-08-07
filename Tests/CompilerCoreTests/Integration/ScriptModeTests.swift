#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ScriptModeTests {

    @Test func testScriptTopLevelStatementsCompileToKIR() throws {
        let source = """
        println("hello from script")
        val x = 1 + 2
        println(x)
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptTopLevelStmts")
    }

    @Test func testScriptTopLevelValVarPropertiesCompileToKIR() throws {
        let source = """
        val greeting = "hello"
        var counter = 0
        counter = counter + 1
        println(greeting)
        println(counter)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            let scriptFile = ast.files.first(where: { !$0.scriptBody.isEmpty })
            #expect(scriptFile != nil, "Script file must have a non-empty scriptBody for top-level val/var")
            #expect(!ctx.diagnostics.hasError, "Top-level val/var in script mode should not produce errors")
        }
    }

    @Test func testScriptLevelFunctionDefinitionAlongsideStatements() throws {
        let source = """
        fun double(n: Int): Int = n * 2
        fun main() {
            println(double(21))
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptHelperFun")
    }

    @Test func testParserRootKindIsScriptForExpressionStatements() throws {
        let source = """
        println("hello")
        1 + 2
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try LoadSourcesPhase().run(ctx)
            try LexPhase().run(ctx)
            try ParsePhase().run(ctx)

            let rootKinds = ctx.syntaxTrees.map { $0.1.node($0.2).kind }
            #expect(
                rootKinds.contains(.script),
                "A file with top-level expression statements must parse as .script, got: \(rootKinds)"
            )
        }
    }

    @Test func testBuildASTSynthesisesMainForScriptBody() throws {
        let source = """
        val x = 42
        println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            let scriptFile = ast.files.first(where: { !$0.scriptBody.isEmpty })
            #expect(scriptFile != nil, "scriptBody must be populated after BuildASTPhase for a script file")

            let topLevelDeclNames: [String] = (scriptFile?.topLevelDecls ?? []).compactMap { declID in
                guard let decl = ast.arena.decl(declID) else { return nil }
                if case let .funDecl(f) = decl { return ctx.interner.resolve(f.name) }
                return nil
            }
            #expect(
                topLevelDeclNames.contains("main"),
                "BuildASTPhase must synthesise a 'main' entry for script content, got: \(topLevelDeclNames)"
            )
        }
    }

    @Test func testScriptArithmeticExpressionCompilesToKIR() throws {
        let source = """
        val a = 3
        val b = 7
        a * b
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptArithLastExpr")
    }

    @Test func testScriptStringConcatenationCompilesToKIR() throws {
        let source = """
        println("hello" + " " + "world")
        val greeting = "hi"
        println(greeting + "!")
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptStringConcat")
    }

    @Test func testScriptMixedValAndExpressionStatementsCompileToKIR() throws {
        let source = """
        val x = 10
        println("start")
        val y = x * 2
        println(y)
        val z = x + y
        z
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptMixedValsAndExprs")
    }

    @Test func testScriptBodyContainsMultipleExpressions() throws {
        let source = """
        val a = 1
        val b = 2
        val c = a + b
        println(c)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            let scriptFile = ast.files.first(where: { !$0.scriptBody.isEmpty })
            let count = scriptFile?.scriptBody.count ?? 0
            #expect(count > 1, "scriptBody should contain multiple expressions for a multi-statement script")
        }
    }

    @Test func testParserRootKindIsScriptWhenFunDeclCoexistsWithStatement() throws {
        let source = """
        fun greet(name: String): String = "Hello, " + name
        println(greet("World"))
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try LoadSourcesPhase().run(ctx)
            try LexPhase().run(ctx)
            try ParsePhase().run(ctx)

            let rootKinds = ctx.syntaxTrees.map { $0.1.node($0.2).kind }
            #expect(
                rootKinds.contains(.script),
                "A file mixing a top-level fun decl with a top-level statement must parse as .script, got: \(rootKinds)"
            )
        }
    }

    @Test func testScriptTopLevelFunctionIsNotDuplicatedAsLocalDecl() throws {
        let source = """
        fun greet(name: String): String = "Hello, " + name
        println(greet("World"))
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            let scriptFile = try #require(ast.files.first(where: { !$0.scriptBody.isEmpty }))

            let topLevelFunNames: [String] = scriptFile.topLevelDecls.compactMap { declID in
                guard let decl = ast.arena.decl(declID) else { return nil }
                if case let .funDecl(f) = decl { return ctx.interner.resolve(f.name) }
                return nil
            }
            #expect(
                topLevelFunNames.filter { $0 == "greet" }.count == 1,
                "Top-level 'greet' must be registered exactly once, got: \(topLevelFunNames)"
            )
            #expect(topLevelFunNames.contains("main"))

            // The synthesized main() body must not also re-declare `greet` as a
            // shadowing local function; it should only call the top-level one.
            let localFunNamesInScriptBody: [String] = scriptFile.scriptBody.compactMap { exprID in
                guard let expr = ast.arena.expr(exprID) else { return nil }
                guard case let .localFunDecl(name, _, _, _, _, _) = expr else { return nil }
                return ctx.interner.resolve(name)
            }
            #expect(
                !localFunNamesInScriptBody.contains("greet"),
                "greet must not be duplicated as a local decl inside the synthesized main(), got: \(localFunNamesInScriptBody)"
            )
        }
    }

    @Test func testScriptTopLevelFunctionDeclarationAlongsideStatementCompilesToKIR() throws {
        let source = """
        fun greet(name: String): String {
            return "Hello, " + name
        }

        fun add(a: Int, b: Int): Int = a + b

        println(greet("World"))
        println(add(5, 3))
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptTopLevelFunAlongsideStatement")
    }

    @Test func testScriptRecursiveTopLevelFunctionCompilesToKIR() throws {
        let source = """
        fun factorial(n: Int): Int = if (n <= 1) 1 else n * factorial(n - 1)

        println(factorial(5))
        println(factorial(6))
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptRecursiveTopLevelFun")
    }

    @Test func testScriptTopLevelDataClassAndExtensionFunctionsCompileToKIR() throws {
        let source = """
        fun String.isPalindrome(): Boolean {
            return this == this.reversed()
        }

        data class Person(val name: String, val age: Int)

        fun Person.isAdult(): Boolean = age >= 18

        val text = "level"
        val person = Person("Alice", 25)

        println("'" + text + "' is palindrome: " + text.isPalindrome())
        println(person.name + " is adult: " + person.isAdult())
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptTopLevelDataClassAndExtension")
    }

    @Test func testScriptTopLevelGenericExtensionAndVarargFunctionsCompileToKIR() throws {
        let source = """
        fun<T> List<T>.firstMatching(predicate: (T) -> Boolean): T? {
            for (item in this) {
                if (predicate(item)) return item
            }
            return null
        }

        fun printAll(vararg items: Any) {
            items.forEach { println(it) }
        }

        fun calculate(base: Int, multiplier: Int = 2): Int = base * multiplier

        println(listOf(1, 2, 3).firstMatching { it > 2 })
        printAll("Hello", 42, true)
        println(calculate(10))
        println(calculate(10, 3))
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptTopLevelGenericExtensionAndVararg")
    }

    @Test func testScriptFileCoexistsWithRegularKotlinFileInModule() throws {
        let regular = """
        fun helper(x: Int): Int = x + 1
        class Config(val value: Int)
        """
        let script = """
        val n = 5
        println(n)
        """
        try withTemporaryFiles(contents: [regular, script]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            #expect(ast.files.count >= 4, "Both user files + bundled stdlib must produce an ASTFile")

            let scriptFile = ast.files.first(where: { !$0.scriptBody.isEmpty })
            #expect(scriptFile != nil, "One ASTFile must have a non-empty scriptBody")

            let bundledFileCount = ast.files.count - 2
            let regularFile = ast.files.first(where: { $0.scriptBody.isEmpty && $0.fileID.rawValue >= Int32(bundledFileCount) })
            #expect(regularFile != nil, "One ASTFile must have an empty scriptBody")

            #expect(!ctx.diagnostics.hasError, "Mixed script+regular module must compile without errors")
        }
    }
}
#endif
