#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-706: `kotlin.Pair`/`kotlin.Triple` are forward-declared from bundled
/// `Tuples.kt` before early synthetic stub registration runs
/// (`predeclareBundledTupleHeaders`), replacing the deleted
/// `HeaderHelpers+SyntheticPairTripleAnchors.swift`. These tests pin the two
/// review-flagged edge cases: `--no-stdlib` builds (no bundled source, no
/// library import) must still resolve `Pair`/`Triple` as class types instead
/// of losing them to `Any`/`<error>`, and bundled-source builds must keep
/// `kotlin.Pair`'s declSite `nil` so golden semantic dumps are unaffected.
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
    func testBundledSourcePairKeepsNilDeclSiteForGoldenStability() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let pairSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"), ctx.interner.intern("Pair"),
            ]))
            let symbol = try #require(sema.symbols.symbol(pairSymbol))
            #expect(symbol.kind == .class)
            #expect(!symbol.flags.contains(.synthetic), "bundled kotlin.Pair should be the real, non-synthetic declaration")
            #expect(symbol.declSite == nil, "kotlin.Pair must keep a nil declSite so GoldenHarnessDump.isExcludedBundledSymbol doesn't drop it from golden dumps")
        }
    }
}
#endif
