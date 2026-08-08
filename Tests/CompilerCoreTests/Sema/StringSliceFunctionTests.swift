@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-072/073: Consolidated Sema coverage for `String.subSequence`
/// and `String.substring`. A single Sema pass resolves both source packages.
/// `subSequence` is deprecated and emits `KSWIFTK-SEMA-DEPRECATED`; `substring`
/// does not.
@Suite
struct StringSliceFunctionTests {
    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    @Test
    func testStringSliceFunctionsResolveInSource() throws {
        let sources: [String] = [
            """
            package sample0
            @Suppress("KSWIFTK-SEMA-DEPRECATED")
            fun headTwo(s: String): String {
                return s.subSequence(0, 2)
            }

            @Suppress("KSWIFTK-SEMA-DEPRECATED")
            fun tailThree(s: String): String {
                return s.subSequence(s.length - 3, s.length)
            }

            @Suppress("KSWIFTK-SEMA-DEPRECATED")
            fun emptySlice(s: String): String {
                return s.subSequence(1, 1)
            }

            @Suppress("KSWIFTK-SEMA-DEPRECATED")
            fun subSequenceOfLiteral(): String {
                return "hello world".subSequence(6, 11)
            }

            @Suppress("KSWIFTK-SEMA-DEPRECATED")
            fun subSequenceInBranch(s: String, take: Boolean): String {
                return if (take) s.subSequence(0, 1) else s.subSequence(1, 2)
            }

            fun useSubSequence(s: String): String {
                return s.subSequence(0, 2)
            }
            """,
            """
            package sample1
            fun headTwo(s: String): String {
                return s.substring(0, 2)
            }

            fun fromIndex(s: String): String {
                return s.substring(3)
            }

            fun substringOfLiteral(): String {
                return "hello world".substring(6, 11)
            }

            fun emptySliceOfLiteral(): String {
                return "abc".substring(1, 1)
            }

            fun substringInBranch(s: String, take: Boolean): String {
                return if (take) s.substring(0, 1) else s.substring(1)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            for path in paths {
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                let errors = pathDiagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected slice function to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            // === subSequence ===
            do {
                let path = paths[0]
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                #expect(
                    pathDiagnostics.contains { $0.code == "KSWIFTK-SEMA-DEPRECATED" },
                    "Expected String.subSequence(...) to emit a deprecation diagnostic in sample0"
                )

                let fq = ["kotlin", "text", "subSequence"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == sema.types.stringType
                        && signature.parameterTypes.count == 2
                        && signature.parameterTypes.allSatisfy { $0 == sema.types.intType }
                })
                #expect(
                    sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.stringType,
                    "String.subSequence(startIndex, endIndex) should return String"
                )
                #expect(
                    sema.symbols.externalLinkName(for: symbol) == nil,
                    "String.subSequence(...) is source-backed and must not link to a runtime helper"
                )
            }

            // === substring ===
            do {
                let fq = ["kotlin", "text", "substring"].map { interner.intern($0) }

                let twoArgSymbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == sema.types.stringType
                        && signature.parameterTypes.count == 2
                        && signature.parameterTypes.allSatisfy { $0 == sema.types.intType }
                })
                #expect(
                    sema.symbols.functionSignature(for: twoArgSymbol)?.returnType == sema.types.stringType,
                    "String.substring(startIndex, endIndex) should return String"
                )
                #expect(
                    sema.symbols.externalLinkName(for: twoArgSymbol) == nil,
                    "String.substring(startIndex, endIndex) is source-backed"
                )

                let oneArgSymbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == sema.types.stringType
                        && signature.parameterTypes.count == 1
                        && signature.parameterTypes[0] == sema.types.intType
                })
                #expect(
                    sema.symbols.functionSignature(for: oneArgSymbol)?.returnType == sema.types.stringType,
                    "String.substring(startIndex) should return String"
                )
                #expect(
                    sema.symbols.externalLinkName(for: oneArgSymbol) == nil,
                    "String.substring(startIndex) is source-backed"
                )
            }
        }
    }
}
