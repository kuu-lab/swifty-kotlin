@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-050/053: Consolidated Sema coverage for `String.removePrefix`
/// and `String.removeSurrounding`. A single Sema pass resolves all source packages
/// and each `do` block verifies the expected symbols have no C external link.
@Suite
struct StringPrefixSuffixFunctionTests {
    @Test
    func testPrefixAndSuffixFunctionsResolveInSource() throws {
        let sources: [String] = [
            """
            package sample0
            fun stripScheme(s: String): String {
                return s.removePrefix("https://")
            }

            fun stripFromLiteral(): String {
                return "HelloWorld".removePrefix("Hello")
            }

            fun stripFromExpression(value: Int): String {
                return value.toString().removePrefix("0")
            }

            fun stripInBranch(s: String): String {
                return if (s.removePrefix("foo").isEmpty()) "empty" else s.removePrefix("foo")
            }

            fun stripChained(s: String): String {
                return s.removePrefix("a").removePrefix("b")
            }
            """,
            """
            package sample1
            fun stripBrackets(s: String): String {
                return s.removeSurrounding("[")
            }

            fun stripTripleAsterisk(): String {
                return "***star***".removeSurrounding("***")
            }

            fun stripExactMatch(): String {
                return "ab".removeSurrounding("ab")
            }

            fun stripNoMatchSingle(s: String): String {
                return "abc".removeSurrounding("ab")
            }

            fun stripChained(s: String): String {
                return s.removeSurrounding("(").removeSurrounding(")")
            }

            fun stripDiv(s: String): String {
                return s.removeSurrounding("<div>", "</div>")
            }

            fun stripBracketItem(): String {
                return "[item]".removeSurrounding("[", "]")
            }

            fun stripNoMatchPair(): String {
                return "no-match".removeSurrounding("<", ">")
            }

            fun stripFromExpression(value: Int): String {
                return value.toString().removeSurrounding("(", ")")
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let names = ["removePrefix", "removeSurrounding"]
            for (index, name) in names.enumerated() {
                let path = paths[index]
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                let errors = pathDiagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected \(name) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // === removePrefix ===
            do {
                let fq = ["kotlin", "text", "removePrefix"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.receiverType == sema.types.stringType
                        && signature.returnType == sema.types.stringType
                })
                #expect(
                    sema.symbols.externalLinkName(for: symbol) == nil,
                    "String.removePrefix should be source-backed (no runtime link) after KSP-404"
                )
            }

            // === removeSurrounding ===
            do {
                let fq = ["kotlin", "text", "removeSurrounding"].map { interner.intern($0) }
                let symbols = sema.symbols.lookupAll(fqName: fq)

                let oneArgSymbol = try #require(symbols.first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == sema.types.stringType
                        && signature.parameterTypes.count == 1
                        && signature.returnType == sema.types.stringType
                })
                #expect(
                    sema.symbols.externalLinkName(for: oneArgSymbol) == nil,
                    "String.removeSurrounding(delimiter) should be source-backed after KSP-404"
                )

                let twoArgSymbol = try #require(symbols.first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == sema.types.stringType
                        && signature.parameterTypes.count == 2
                        && signature.returnType == sema.types.stringType
                })
                #expect(
                    sema.symbols.externalLinkName(for: twoArgSymbol) == nil,
                    "String.removeSurrounding(prefix, suffix) should be source-backed after KSP-404"
                )
            }
        }
    }
}
