@testable import CompilerCore
import Foundation
import Testing

func assertSequenceSourceExtensionResolves(
    source: String,
    functionName: String,
    diagnosticContext: String
) throws {
    try withTemporaryFile(contents: source) { path in
        let ctx = makeCompilationContext(inputs: [path])
        try runSema(ctx)
        let diagnosticSummary = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: " | ")
        #expect(
            !ctx.diagnostics.hasError,
            "Expected \(diagnosticContext) surface to resolve cleanly, got: \(diagnosticSummary)"
        )

        let sema = try #require(ctx.sema)
        let packageNameLists = [
            ["kotlin", "sequences", functionName],
            ["kotlin", "collections", functionName],
        ]
        let symbolID = try #require(
            packageNameLists
                .map { $0.map { ctx.interner.intern($0) } }
                .first { sema.symbols.lookup(fqName: $0) != nil }
                .flatMap { sema.symbols.lookup(fqName: $0) },
            "Expected \(diagnosticContext) source extension to be registered"
        )
        #expect(
            sema.symbols.symbol(symbolID)?.declSite != nil,
            "Expected \(diagnosticContext) to resolve to bundled Kotlin source"
        )
        #expect(
            sema.symbols.externalLinkName(for: symbolID) == nil,
            "Expected \(diagnosticContext) source extension to have no synthetic external link"
        )
    }
}

func assertSequenceMemberResolves(
    source: String,
    memberName: String,
    expectedLinkName: String,
    diagnosticContext: String
) throws {
    try withTemporaryFile(contents: source) { path in
        let ctx = makeCompilationContext(inputs: [path])
        try runSema(ctx)
        let diagnosticSummary = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: " | ")
        #expect(
            !ctx.diagnostics.hasError,
            "Expected \(diagnosticContext) surface to resolve cleanly, got: \(diagnosticSummary)"
        )

        let sema = try #require(ctx.sema)
        let memberFQName = ["kotlin", "sequences", "Sequence", memberName]
            .map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: memberFQName)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(
            links.contains(expectedLinkName),
            "Expected '\(expectedLinkName)' in resolved link names \(links.sorted()) for \(diagnosticContext)"
        )
    }
}
