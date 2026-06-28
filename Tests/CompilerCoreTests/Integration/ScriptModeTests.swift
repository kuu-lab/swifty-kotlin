@testable import CompilerCore
import Foundation
import XCTest

final class ScriptModeTests: XCTestCase {

    func testScriptTopLevelStatementsCompileToKIR() throws {
        let source = """
        println("hello from script")
        val x = 1 + 2
        println(x)
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptTopLevelStmts")
    }

    func testScriptTopLevelValVarPropertiesCompileToKIR() throws {
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

            let ast = try XCTUnwrap(ctx.ast)
            let scriptFile = ast.files.first(where: { !$0.scriptBody.isEmpty })
            XCTAssertNotNil(scriptFile, "Script file must have a non-empty scriptBody for top-level val/var")
            XCTAssertFalse(ctx.diagnostics.hasError, "Top-level val/var in script mode should not produce errors")
        }
    }

    func testScriptLevelFunctionDefinitionAlongsideStatements() throws {
        let source = """
        fun double(n: Int): Int = n * 2
        fun main() {
            println(double(21))
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptHelperFun")
    }

    func testParserRootKindIsScriptForExpressionStatements() throws {
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
            XCTAssertTrue(rootKinds.contains(.script),
                          "A file with top-level expression statements must parse as .script, got: \(rootKinds)")
        }
    }

    func testBuildASTSynthesisesMainForScriptBody() throws {
        let source = """
        val x = 42
        println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let scriptFile = ast.files.first(where: { !$0.scriptBody.isEmpty })
            XCTAssertNotNil(scriptFile, "scriptBody must be populated after BuildASTPhase for a script file")

            let topLevelDeclNames: [String] = (scriptFile?.topLevelDecls ?? []).compactMap { declID in
                guard let decl = ast.arena.decl(declID) else { return nil }
                if case let .funDecl(f) = decl { return ctx.interner.resolve(f.name) }
                return nil
            }
            XCTAssertTrue(topLevelDeclNames.contains("main"),
                          "BuildASTPhase must synthesise a 'main' entry for script content, got: \(topLevelDeclNames)")
        }
    }

    func testScriptArithmeticExpressionCompilesToKIR() throws {
        let source = """
        val a = 3
        val b = 7
        a * b
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptArithLastExpr")
    }

    func testScriptStringConcatenationCompilesToKIR() throws {
        let source = """
        println("hello" + " " + "world")
        val greeting = "hi"
        println(greeting + "!")
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptStringConcat")
    }

    func testScriptMixedValAndExpressionStatementsCompileToKIR() throws {
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

    func testScriptBodyContainsMultipleExpressions() throws {
        let source = """
        val a = 1
        val b = 2
        val c = a + b
        println(c)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let scriptFile = ast.files.first(where: { !$0.scriptBody.isEmpty })
            let count = scriptFile?.scriptBody.count ?? 0
            XCTAssertGreaterThan(count, 1,
                                 "scriptBody should contain multiple expressions for a multi-statement script")
        }
    }

    func testScriptFileCoexistsWithRegularKotlinFileInModule() throws {
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

            let ast = try XCTUnwrap(ctx.ast)
            // 2 user files + 5 bundled stdlib files (collections + text + atomic + sequences + time)
            XCTAssertEqual(ast.files.count, 7, "Both user files + bundled stdlib must produce an ASTFile")

            let scriptFile = ast.files.first(where: { !$0.scriptBody.isEmpty })
            XCTAssertNotNil(scriptFile, "One ASTFile must have a non-empty scriptBody")

            let regularFile = ast.files.first(where: { $0.scriptBody.isEmpty && $0.fileID.rawValue >= 5 })
            XCTAssertNotNil(regularFile, "One ASTFile must have an empty scriptBody")

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "Mixed script+regular module must compile without errors")
        }
    }
}
