#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-706: `kotlin.Pair`/`kotlin.Triple` are forward-declared from bundled
/// `Tuples.kt`/`Pair/Stdlib.kt` before early synthetic stub registration runs
/// (`predeclareBundledTupleHeaders`), replacing the deleted
/// `HeaderHelpers+SyntheticPairTripleAnchors.swift`. These tests pin the two
/// review-flagged edge cases: `--no-stdlib` builds (no bundled source, no
/// library import) must still resolve `Pair`/`Triple` as class types instead
/// of losing them to `Any`/`<error>`, and bundled-source builds must bind
/// `kotlin.Pair`/`kotlin.Triple`/`kotlin.text.Charset` to their real bundled
/// declarations (source-backed, non-synthetic, owned by the bundled file) so
/// no fake declaration position is needed for golden dump stability.
@Suite
struct PairTripleNominalAnchorTests {
    @Test
    func testNoStdlibStillResolvesPairAndTripleAsClassTypes() throws {
        // Bare synthetic anchors carry no constructor/members (matching the
        // deleted anchor file's behavior), so this only exercises type
        // resolution -- an identity function, not a `Pair(...)` call -- which
        // is exactly what the flagged zip/partition/unzip stub signatures need.
        let source = """
        fun passThroughPair(p: Pair<Int, String>): Pair<Int, String> = p
        fun passThroughTriple(t: Triple<Int, String, Boolean>): Triple<Int, String, Boolean> = t
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "no-stdlib Pair/Triple usage should not error: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let pairSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"), ctx.interner.intern("Pair"),
            ]))
            let tripleSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"), ctx.interner.intern("Triple"),
            ]))
            #expect(sema.symbols.symbol(pairSymbol)?.kind == .class)
            #expect(sema.symbols.symbol(tripleSymbol)?.kind == .class)

            let passThroughSymbol = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("passThroughPair")]).first)
            let passThroughReturnType = try #require(sema.symbols.functionSignature(for: passThroughSymbol)?.returnType)
            let resolved = try #require(resolveClassTypeSymbol(passThroughReturnType, sema: sema))
            #expect(resolved.symbol.id == pairSymbol, "passThroughPair()'s return type should resolve to the same kotlin.Pair symbol, not Any/<error>")
        }
    }

    @Test
    func testBundledSourceTupleNominalsStaySourceBacked() throws {
        // RF-GOLDEN-009: declaration ownership, required flags, and type
        // resolution are compiler contracts -- none of them may depend on how
        // the golden harness classifies or renders symbols.
        let source = """
        fun passThroughPair(p: Pair<Int, String>): Pair<Int, String> = p
        fun passThroughCharset(c: kotlin.text.Charset): kotlin.text.Charset = c
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let expectations: [(names: [String], ownerFile: String)] = [
                (["kotlin", "Pair"], "__bundled_kotlin/Pair/Stdlib.kt"),
                (["kotlin", "Triple"], "__bundled_kotlin/Tuples.kt"),
                (["kotlin", "text", "Charset"], "__bundled_kotlin/text/StringEncoding.kt"),
            ]
            var pairSymbol: SymbolID?
            for (names, ownerFilePath) in expectations {
                let fqName = names.map { ctx.interner.intern($0) }
                let symbolID = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "\(names.joined(separator: ".")) should resolve"
                )
                let symbol = try #require(sema.symbols.symbol(symbolID))
                #expect(symbol.kind == .class, "\(names.joined(separator: ".")) should be a class")
                #expect(symbol.visibility == .public)
                #expect(!symbol.flags.contains(.synthetic), "\(names.joined(separator: ".")) should be the real bundled declaration, not a shell")
                let ownerFile = try #require(
                    sema.symbols.sourceFileID(for: symbolID),
                    "\(names.joined(separator: ".")) should track its owning file"
                )
                #expect(ctx.sourceManager.path(of: ownerFile) == ownerFilePath)
                let declSite = try #require(symbol.declSite, "\(names.joined(separator: ".")) keeps its real declaration site")
                #expect(declSite.start.file == ownerFile)
                #expect(sema.symbols.isSourceBackedSymbol(symbolID))
                if names.last == "Pair" {
                    pairSymbol = symbolID
                }
            }

            // Type resolution binds user signatures to the same symbols.
            let passThroughPairSymbol = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("passThroughPair")]).first)
            let pairReturnType = try #require(sema.symbols.functionSignature(for: passThroughPairSymbol)?.returnType)
            #expect(resolveClassTypeSymbol(pairReturnType, sema: sema)?.symbol.id == pairSymbol)

            let charsetSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"), ctx.interner.intern("text"), ctx.interner.intern("Charset"),
            ]))
            let passThroughCharsetSymbol = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("passThroughCharset")]).first)
            let charsetReturnType = try #require(sema.symbols.functionSignature(for: passThroughCharsetSymbol)?.returnType)
            #expect(resolveClassTypeSymbol(charsetReturnType, sema: sema)?.symbol.id == charsetSymbol)
        }
    }
}
#endif
