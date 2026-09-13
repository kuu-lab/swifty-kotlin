#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension LexerParserEdgeCaseTests {
    @Test
    func testFrontendPhasesBuildASTForMixedDeclarations() throws {
        let source = """
        package demo
        import demo.util.*

        public inline suspend fun hello(name: String) = "hi" + name
        val answer = 42
        var status = 1
        class C<T>(x: T)
        interface I
        object O
        typealias Alias = String
        enum class Colors { Red, Green }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runFrontend(ctx)

            #expect(ctx.syntaxTree != nil)
            #expect(!(ctx.tokens.isEmpty))

            let ast = try #require(ctx.ast)
            #expect(ast.files.count == 1)
            #expect(ast.declarationCount >= 6)
            #expect(!(ctx.diagnostics.hasError))
        }
    }

    @Test
    func testParserKeepsFollowingDeclarationAfterBrokenFunctionHeader() throws {
        let source = """
        fun ()
        fun good(): Int = 1
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            #expect(ast.arena.declarations().count == 2)
            #expect(topLevelFunction(named: "good", in: ast, interner: ctx.interner) != nil)
        }
    }

    @Test
    func testParserUsesScriptRootForTopLevelStatementsOnly() {
        let parsed = parse(
            """
            1 + 2
            """
        )
        #expect(parsed.arena.node(parsed.root).kind == .script)
    }

    @Test
    func testSemaCollectsNestedTypeAliasSymbolsInClassAndObject() throws {
        let source = """
        class Box {
            typealias Elem = Int
        }
        object Holder {
            typealias Value = String
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)

            let sema = try #require(ctx.sema)
            let all = sema.symbols.allSymbols()
            func hasNestedTypeAlias(_ name: String, nestedIn parent: String) -> Bool {
                all.contains { symbol in
                    symbol.kind == .typeAlias &&
                        ctx.interner.resolve(symbol.name) == name &&
                        symbol.fqName.count >= 2 &&
                        ctx.interner.resolve(symbol.fqName[symbol.fqName.count - 2]) == parent
                }
            }

            #expect(hasNestedTypeAlias("Elem", nestedIn: "Box"))
            #expect(hasNestedTypeAlias("Value", nestedIn: "Holder"))
        }
    }

    @Test
    func testExpressionBodyParsesReturnIfTryWithoutTypeDiagnostics() throws {
        let source = """
        fun demo(flag: Boolean): Int = if (flag) return 1 else try 2 catch (e: Throwable) 3
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.hasError))
        }
    }

    @Test
    func testUnaryExpressionsParseAndTypeCheckWithoutErrors() throws {
        let source = """
        fun demo(x: Int): Int = if (!false) -x + +x else 0
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.hasError))
        }
    }

    @Test
    func testComparisonAndLogicalExpressionsParseAndTypeCheckWithoutErrors() throws {
        let source = """
        fun demoA(x: Int): Int = if (x != 0 && x < 10 || x >= 100) 1 else 2
        fun demoB(x: Int): Int = if (x <= 20 && x > 3) 2 else 3
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.hasError))
        }
    }

    @Test
    func testMultiFileParseBoundaryProducesPerFileASTFiles() throws {
        let fileA = """
        package demo
        fun greet(name: String) = "Hello"
        class Greeter
        """
        let fileB = """
        package demo
        import demo.*
        fun farewell(name: String) = "Bye"
        object Singleton
        """

        try withTemporaryFiles(contents: [fileA, fileB]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            #expect(ast.files.count == 2)

            #expect(ctx.tokensByFile.count == ast.files.count)
            #expect(ctx.syntaxTrees.count == ast.files.count)

            for (_, fileTokens) in ctx.tokensByFile {
                #expect(fileTokens.last?.kind == .eof)
            }

            let file0 = ast.files[0]
            let file1 = ast.files[1]
            #expect(file0.fileID != file1.fileID)

            let file0DeclNames = topLevelDeclNames(of: file0, in: ast, interner: ctx.interner)
            let file1DeclNames = topLevelDeclNames(of: file1, in: ast, interner: ctx.interner)

            #expect(file0DeclNames.contains("greet"))
            #expect(file0DeclNames.contains("Greeter"))
            #expect(!(file0DeclNames.contains("farewell")))

            #expect(file1DeclNames.contains("farewell"))
            #expect(file1DeclNames.contains("Singleton"))
            #expect(!(file1DeclNames.contains("greet")))
        }
    }

    @Test
    func testMultiFileCrossFileBoundaryDoesNotConcatenateStatements() throws {
        let fileA = """
        fun alpha() = 1
        """
        let fileB = """
        fun beta() = 2
        """

        try withTemporaryFiles(contents: [fileA, fileB]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            #expect(ast.files.count == 2)

            let allFunNames = ast.arena.declarations().compactMap { decl -> String? in
                guard case let .funDecl(f) = decl else { return nil }
                return ctx.interner.resolve(f.name)
            }
            #expect(allFunNames.contains("alpha"))
            #expect(allFunNames.contains("beta"))

            #expect(ctx.syntaxTrees.count == ast.files.count)
            for (_, cst, root) in ctx.syntaxTrees {
                #expect(cst.node(root).kind == .kotlinFile)
            }

            #expect(!(ctx.diagnostics.hasError))
        }
    }

    @Test
    func testMultiFilePerFileScriptAndKotlinFileDetermination() throws {
        let fileA = """
        fun helper() = 42
        class MyClass
        """
        let fileB = """
        1 + 2
        """

        try withTemporaryFiles(contents: [fileA, fileB]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            #expect(ast.files.count == 2)
            #expect(ctx.syntaxTrees.count == ast.files.count)

            let rootKinds = ctx.syntaxTrees.map { $0.1.node($0.2).kind }
            #expect(rootKinds.contains(.kotlinFile))
            #expect(rootKinds.contains(.script))

            #expect(ast.files.contains { !$0.scriptBody.isEmpty })

            let kotlinFile = try #require(ast.files.first(where: { $0.scriptBody.isEmpty }))
            let kotlinDeclNames = topLevelDeclNames(of: kotlinFile, in: ast, interner: ctx.interner)
            #expect(kotlinDeclNames.contains("helper"))
            #expect(kotlinDeclNames.contains("MyClass"))

            #expect(!(ctx.diagnostics.hasError))
        }
    }

    @Test
    func testCharEscapeSequencesProduceCorrectScalarValues() {
        let source = "'\\t' '\\n' '\\r' '\\\\' '\\'' '\\\"' '\\$'"
        let result = lex(source)
        #expect(charValues(in: result.tokens) == [9, 10, 13, 92, 39, 34, 36])
        #expect(!(result.diagnostics.hasError))
    }

    @Test
    func testUnicodeEscapeInCharLiteralProducesCorrectScalar() {
        // A bare 'A' and its \u0041 escape must both land on 65.
        let source = "'A' '\\u0041' '\\u0000' '\\uFFFF' '\\u2764'"
        let result = lex(source)
        #expect(charValues(in: result.tokens) == [65, 65, 0, 65535, 10084])
        #expect(!(result.diagnostics.hasError))
    }

    @Test
    func testInvalidEscapeSequenceEmitsDiagnostic() {
        let source = "'\\q'"
        let result = lex(source)
        assertHasDiagnostic("KSWIFTK-LEX-0003", in: result.diagnostics.diagnostics)
    }

    @Test
    func testCharLiteralSupportsSingleNonASCIIScalar() {
        let source = "'あ'"
        let result = lex(source)
        #expect(charValues(in: result.tokens) == [0x3042])
        #expect(!(result.diagnostics.hasError))
    }

    @Test
    func testCharLiteralEmptyAndMultipleCharactersEmitLex0003() {
        let source = "'' 'ab'"
        let result = lex(source)
        assertDiagnosticCount("KSWIFTK-LEX-0003", expected: 2, in: result.diagnostics.diagnostics)
        assertNoDiagnostic("KSWIFTK-LEX-0002", in: result.diagnostics.diagnostics)
    }

    @Test
    func testCharLiteralUnicodeEscapeRequiresUXXXXForm() {
        let source = "'\\u{0041}' '\\u12G4'"
        let result = lex(source)
        assertDiagnosticCount("KSWIFTK-LEX-0003", expected: 2, in: result.diagnostics.diagnostics)
        assertNoDiagnostic("KSWIFTK-LEX-0002", in: result.diagnostics.diagnostics)
    }

    @Test
    func testCharArithmeticTypeInference() throws {
        let source = """
        fun test() {
            val a = 'a' + 1
            val b = 'z' - 'a'
            val c = 'z' - 1
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let binaryTypes = binaryExprTypes(ast: ast, sema: sema)

            // 'a' + 1 -> Char, 'z' - 'a' -> Int, 'z' - 1 -> Char
            #expect(binaryTypes.contains("add:Char"), "Expected 'a' + 1 to produce Char, got: \(binaryTypes)")
            #expect(binaryTypes.contains("subtract:Int"), "Expected 'z' - 'a' to produce Int, got: \(binaryTypes)")
            #expect(binaryTypes.contains("subtract:Char"), "Expected 'z' - 1 to produce Char, got: \(binaryTypes)")
            #expect(!(ctx.diagnostics.hasError))
        }
    }

    @Test
    func testCharCompoundAssignmentPreservesCharType() throws {
        let source = """
        fun test() {
            var a: Char = 'a'
            a += 1
            var b: Char = 'z'
            b -= 1
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            // Compound assignment on Char should not produce errors
            // (would fail if type corrupted to Int, causing subsequent mismatches)
            #expect(!(ctx.diagnostics.hasError), "Char compound assignment should not produce errors, got: \(ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" })")
        }
    }

    @Test
    func testNumericBinaryOpsNotBrokenByCharChanges() throws {
        let source = """
        fun test() {
            val a = 1 + 2
            val b = 1.0 + 2
            val c = 10L - 3
            val d = "hello" + 1
            val e = 1.0f * 2
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let binaryTypes = binaryExprTypes(ast: ast, sema: sema)

            // Int + Int -> Int, Double + Int -> Double, Long - Int -> Long,
            // String + Int -> String, Float * Int -> Float
            #expect(binaryTypes.contains("add:Int"), "Expected Int + Int -> Int, got: \(binaryTypes)")
            #expect(binaryTypes.contains("add:Double"), "Expected Double + Int -> Double, got: \(binaryTypes)")
            #expect(binaryTypes.contains("subtract:Long"), "Expected Long - Int -> Long, got: \(binaryTypes)")
            #expect(binaryTypes.contains("add:String"), "Expected String + Int -> String, got: \(binaryTypes)")
            #expect(binaryTypes.contains("multiply:Float"), "Expected Float * Int -> Float, got: \(binaryTypes)")
            #expect(!(ctx.diagnostics.hasError))
        }
    }

    @Test
    func testBodyLessExternalFunctionDoesNotConsumeFollowingDeclaration() {
        let source = """
        package demo

        external fun foo(): Int

        val x = 1
        """
        let parsed = parse(source)
        let topLevel = parsed.arena.children(of: parsed.root).compactMap { child -> SyntaxKind? in
            guard case let .node(id) = child else { return nil }
            return parsed.arena.node(id).kind
        }
        #expect(topLevel == [.packageHeader, .funDecl, .propertyDecl])
        #expect(!(parsed.diagnostics.hasError))
    }
}

/// `"<op>:<renderedType>"` for every binary expression in the arena, in arena
/// order. Note this spans bundled stdlib expressions too, which is why callers
/// assert with `contains` rather than on the whole list.
private func binaryExprTypes(ast: ASTModule, sema: SemaModule) -> [String] {
    ast.arena.exprs.indices.compactMap { index in
        let exprID = ExprID(rawValue: Int32(index))
        guard let expr = ast.arena.expr(exprID),
              case let .binary(op, _, _, _) = expr,
              let exprType = sema.bindings.exprTypes[exprID]
        else {
            return nil
        }
        return "\(op):\(sema.types.renderType(exprType))"
    }
}
#endif
