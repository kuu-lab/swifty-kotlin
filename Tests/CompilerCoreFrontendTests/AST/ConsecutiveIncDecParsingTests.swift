#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ConsecutiveIncDecParsingTests {
    @Test(arguments: [
        "x++ ++x",
        "x-- --x",
        "x++ --x",
        "x-- ++x",
        "x++++x",
        "x++ ++",
        "5++",
        "f()++",
        "a[i]++ ++x",
    ])
    func rejectsStrayIncrementDecrementAfterExpression(_ source: String) {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        _ = parser.parse()

        #expect(lexed.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0018" && $0.severity == .error
        }, "Expected KSWIFTK-PARSE-0018 for \(source), got: \(lexed.diagnostics.diagnostics.map(\.message))")
    }

    @Test(arguments: [
        "++x ++x",
        "++ ++x",
    ])
    func rejectsPrefixIncDecWithNonVariableOperand(_ source: String) {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        _ = parser.parse()

        #expect(lexed.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0001" && $0.severity == .error
        }, "Expected KSWIFTK-PARSE-0001 for \(source), got: \(lexed.diagnostics.diagnostics.map(\.message))")
    }

    @Test(arguments: [
        "x++",
        "++x",
        "x--",
        "--x",
        "a[i]++",
        "++a[i]",
        "x++ + +x",
        "x+++x",
        "x - -y",
        "(x)++",
    ])
    func acceptsValidIncDecForms(_ source: String) {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        #expect(parser.parse() != nil)
        #expect(parser.current() == nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty,
                "Expected no diagnostics for \(source), got: \(lexed.diagnostics.diagnostics.map(\.message))")
    }

    @Test(arguments: [
        "fun main() { var x = 0; x++ ++x; println(x) }",
        "fun main() { var x = 0; x-- --x; println(x) }",
        "fun main() { var x = 0; ++x ++x; println(x) }",
    ])
    func rejectsConsecutiveIncDecStatement(_ source: String) throws {
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runFrontend(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(!errors.isEmpty,
                    "Expected a diagnostic for \(source), got none")
        }
    }

    @Test(arguments: [
        "fun main() { var x = 0; x++; ++x; println(x) }",
        "fun main() { var x = 0; x++\n ++x\n println(x) }",
        "fun main() { var x = 0; val y = x++ + +x; println(y) }",
    ])
    func acceptsSeparatedIncDecStatements(_ source: String) throws {
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runFrontend(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty,
                    "Expected no errors for \(source), got: \(errors.map(\.message))")
        }
    }
}
#endif
