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
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            #expect(ctx.syntaxTree != nil)
            #expect(ctx.ast != nil)
            #expect(!(ctx.tokens.isEmpty))

            let ast = try #require(ctx.ast)
            // 1 user file + 3 bundled stdlib files (collections, text + sequences)
            #expect(ast.files.count == 5)
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
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            let declarations = ast.arena.declarations()
            #expect(declarations.count >= 2)

            let names: [String] = declarations.compactMap { decl in
                guard case let .funDecl(funDecl) = decl else {
                    return nil
                }
                return ctx.interner.resolve(funDecl.name)
            }
            #expect(names.contains("good"))
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
            let elem = all.first(where: { symbol in
                symbol.kind == .typeAlias &&
                    ctx.interner.resolve(symbol.name) == "Elem" &&
                    symbol.fqName.count >= 2 &&
                    ctx.interner.resolve(symbol.fqName[symbol.fqName.count - 2]) == "Box"
            })
            let value = all.first(where: { symbol in
                symbol.kind == .typeAlias &&
                    ctx.interner.resolve(symbol.name) == "Value" &&
                    symbol.fqName.count >= 2 &&
                    ctx.interner.resolve(symbol.fqName[symbol.fqName.count - 2]) == "Holder"
            })

            #expect(elem != nil)
            #expect(value != nil)
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
            #expect(!(ctx.diagnostics.diagnostics.contains { $0.severity == .error }))
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
            #expect(!(ctx.diagnostics.diagnostics.contains { $0.severity == .error }))
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
            #expect(!(ctx.diagnostics.diagnostics.contains { $0.severity == .error }))
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
            let ctx = makeCompilationContext(inputs: paths)
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            // 2 user files + 2 bundled stdlib files (collections + text)
            #expect(ast.files.count == 6)

            #expect(ctx.tokensByFile.count == 6)
            #expect(ctx.syntaxTrees.count == 6)

            for (_, fileTokens) in ctx.tokensByFile {
                #expect(fileTokens.last.map { $0.kind == .eof } ?? false)
            }

            // Skip bundled stdlib files (indices 0 and 1), user files at indices 2 and 3
            let file0 = ast.files[4]
            let file1 = ast.files[5]
            #expect(file0.fileID != file1.fileID)

            let file0DeclNames = file0.topLevelDecls.compactMap { declID -> String? in
                guard let decl = ast.arena.decl(declID) else { return nil }
                switch decl {
                case let .funDecl(f): return ctx.interner.resolve(f.name)
                case let .classDecl(c): return ctx.interner.resolve(c.name)
                default: return nil
                }
            }
            let file1DeclNames = file1.topLevelDecls.compactMap { declID -> String? in
                guard let decl = ast.arena.decl(declID) else { return nil }
                switch decl {
                case let .funDecl(f): return ctx.interner.resolve(f.name)
                case let .objectDecl(o): return ctx.interner.resolve(o.name)
                default: return nil
                }
            }

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
            let ctx = makeCompilationContext(inputs: paths)
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            // 2 user files + 2 bundled stdlib files (collections + text)
            #expect(ast.files.count == 6)

            let allFunNames = ast.arena.declarations().compactMap { decl -> String? in
                guard case let .funDecl(f) = decl else { return nil }
                return ctx.interner.resolve(f.name)
            }
            #expect(allFunNames.contains("alpha"))
            #expect(allFunNames.contains("beta"))
            // 2 user functions + 62 bundled stdlib functions
            #expect(allFunNames.count == 79)

            #expect(ctx.syntaxTrees.count == 6)
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
            let ctx = makeCompilationContext(inputs: paths)
            try runFrontend(ctx)

            let ast = try #require(ctx.ast)
            // 2 user files + 2 bundled stdlib files (collections + text)
            #expect(ast.files.count == 6)
            #expect(ctx.syntaxTrees.count == 6)

            let rootKinds = ctx.syntaxTrees.map { $0.1.node($0.2).kind }
            #expect(rootKinds.contains(.kotlinFile))
            #expect(rootKinds.contains(.script))

            let scriptFile = ast.files.first(where: { !$0.scriptBody.isEmpty })
            #expect(scriptFile != nil)

            // Find user's .kt file (not bundled stdlib)
            let kotlinFile = ast.files.first(where: { $0.scriptBody.isEmpty && $0.fileID.rawValue >= 4 })
            #expect(kotlinFile != nil)
            let kotlinDeclNames = (kotlinFile?.topLevelDecls ?? []).compactMap { declID -> String? in
                guard let decl = ast.arena.decl(declID) else { return nil }
                switch decl {
                case let .funDecl(f): return ctx.interner.resolve(f.name)
                case let .classDecl(c): return ctx.interner.resolve(c.name)
                default: return nil
                }
            }
            #expect(kotlinDeclNames.contains("helper"))
            #expect(kotlinDeclNames.contains("MyClass"))

            #expect(!(ctx.diagnostics.hasError))
        }
    }

    @Test
    func testCharEscapeSequencesProduceCorrectScalarValues() {
        let source = "'\\t' '\\n' '\\r' '\\\\' '\\'' '\\\"' '\\$'"
        let result = lex(source)
        let charValues = result.tokens.compactMap { token -> UInt32? in
            if case let .charLiteral(value) = token.kind { return value }
            return nil
        }
        #expect(charValues == [9, 10, 13, 92, 39, 34, 36])
        #expect(!(result.diagnostics.hasError))
    }

    @Test
    func testUnicodeEscapeInCharLiteralProducesCorrectScalar() {
        let source = "'\\u0041' '\\u0000' '\\uFFFF' '\\u2764'"
        let result = lex(source)
        let charValues = result.tokens.compactMap { token -> UInt32? in
            if case let .charLiteral(value) = token.kind { return value }
            return nil
        }
        // \u0041 = 'A' = 65, \u0000 = 0, \uFFFF = 65535, \u2764 = 10084
        #expect(charValues == [65, 0, 65535, 10084])
        #expect(!(result.diagnostics.hasError))
    }

    @Test
    func testUnicodeEscapeU0041EqualsCharA() {
        let sourceA = "'A'"
        let sourceUnicode = "'\\u0041'"
        let resultA = lex(sourceA)
        let resultUnicode = lex(sourceUnicode)
        let valueA = resultA.tokens.compactMap { token -> UInt32? in
            if case let .charLiteral(value) = token.kind { return value }
            return nil
        }.first
        let valueUnicode = resultUnicode.tokens.compactMap { token -> UInt32? in
            if case let .charLiteral(value) = token.kind { return value }
            return nil
        }.first
        #expect(valueA == valueUnicode)
        #expect(valueA == 65)
    }

    @Test
    func testInvalidEscapeSequenceEmitsDiagnostic() {
        let source = "'\\q'"
        let result = lex(source)
        let codes = Set(result.diagnostics.diagnostics.map(\.code))
        #expect(codes.contains("KSWIFTK-LEX-0003"))
    }

    @Test
    func testCharLiteralSupportsSingleNonASCIIScalar() {
        let source = "'あ'"
        let result = lex(source)
        let charValues = result.tokens.compactMap { token -> UInt32? in
            if case let .charLiteral(value) = token.kind { return value }
            return nil
        }
        #expect(charValues == [0x3042])
        #expect(!(result.diagnostics.hasError))
    }

    @Test
    func testCharLiteralEmptyAndMultipleCharactersEmitLex0003() {
        let source = "'' 'ab'"
        let result = lex(source)
        let codeCounts = Dictionary(grouping: result.diagnostics.diagnostics, by: \.code).mapValues(\.count)
        #expect(codeCounts["KSWIFTK-LEX-0003"] == 2)
        #expect(codeCounts["KSWIFTK-LEX-0002"] == nil)
    }

    @Test
    func testCharLiteralUnicodeEscapeRequiresUXXXXForm() {
        let source = "'\\u{0041}' '\\u12G4'"
        let result = lex(source)
        let codeCounts = Dictionary(grouping: result.diagnostics.diagnostics, by: \.code).mapValues(\.count)
        #expect(codeCounts["KSWIFTK-LEX-0003"] == 2)
        #expect(codeCounts["KSWIFTK-LEX-0002"] == nil)
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

            // Find binary expressions and check their types
            var binaryTypes: [String] = []
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .binary(op, _, _, _) = expr,
                      let exprType = sema.bindings.exprTypes[exprID]
                else {
                    continue
                }
                let typeName = sema.types.renderType(exprType)
                binaryTypes.append("\(op):\(typeName)")
            }

            // 'a' + 1 -> Char, 'z' - 'a' -> Int, 'z' - 1 -> Char
            #expect(binaryTypes.contains("add:Char"), "Expected 'a' + 1 to produce Char, got: \(binaryTypes)")
            #expect(binaryTypes.contains { $0 == "subtract:Int" }, "Expected 'z' - 'a' to produce Int, got: \(binaryTypes)")
            #expect(binaryTypes.contains { $0 == "subtract:Char" }, "Expected 'z' - 1 to produce Char, got: \(binaryTypes)")
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

            var binaryTypes: [String] = []
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .binary(op, _, _, _) = expr,
                      let exprType = sema.bindings.exprTypes[exprID]
                else {
                    continue
                }
                let typeName = sema.types.renderType(exprType)
                binaryTypes.append("\(op):\(typeName)")
            }

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

    func lex(_ source: String) -> (tokens: [Token], interner: StringInterner, diagnostics: DiagnosticEngine) {
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let lexer = KotlinLexer(
            file: FileID(rawValue: 0),
            source: Data(source.utf8),
            interner: interner,
            diagnostics: diagnostics
        )
        let tokens = lexer.lexAll()
        return (tokens, interner, diagnostics)
    }

    func parse(_ source: String) -> (arena: SyntaxArena, root: NodeID, diagnostics: DiagnosticEngine, interner: StringInterner, tokens: [Token]) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        let parsed = parser.parseFile()
        return (parsed.arena, parsed.root, lexed.diagnostics, lexed.interner, lexed.tokens)
    }
}
#endif
