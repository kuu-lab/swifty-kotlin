#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-TYPE-007 / KSP-486: Validates that `kotlin.text.MatchGroup`
/// exists in the symbol table after sema, exposes the expected `value: String`
/// and `range` properties from bundled Kotlin (so without synthetic runtime
/// links), and that source-level access through `MatchResult.groups[..]`
/// type-checks without diagnostics.
@Suite
struct MatchGroupTypeTests {

    // MARK: - Shared sema fixture

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try #require(result)
    }

    // MARK: - 1. Class symbol registration

    @Test func testMatchGroupClassSymbolIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchGroup"].map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookup(fqName: fq),
            "kotlin.text.MatchGroup class symbol must be registered by sema"
        )
        let info = try #require(sema.symbols.symbol(sym))
        #expect(info.kind == .class,
                       "MatchGroup should be registered with kind=class")
    }

    // MARK: - 2. value: String property

    @Test func testMatchGroupValuePropertyIsRegisteredAndLinked() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchGroup", "value"].map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookup(fqName: fq),
            "MatchGroup.value property must be registered"
        )
        let info = try #require(sema.symbols.symbol(sym))
        #expect(info.kind == .property,
                       "MatchGroup.value should be a property")
        #expect(
            sema.symbols.externalLinkName(for: sym) == nil,
            "MatchGroup.value must be source-backed"
        )
    }

    // MARK: - 3. range property

    @Test func testMatchGroupRangePropertyIsRegisteredAndLinked() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchGroup", "range"].map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookup(fqName: fq),
            "MatchGroup.range property must be registered"
        )
        let info = try #require(sema.symbols.symbol(sym))
        #expect(info.kind == .property,
                       "MatchGroup.range should be a property")
        #expect(
            sema.symbols.externalLinkName(for: sym) == nil,
            "MatchGroup.range must be source-backed"
        )
    }

    // MARK: - 4. Source-level usage of MatchGroup

    @Test func testMatchGroupAccessThroughMatchResultGroupsTypeChecks() throws {
        let ctx = makeContextFromSource("""
        fun firstGroupValue(input: String): String? {
            val regex = Regex("(a)(b)")
            val match = regex.find(input)
            val group: MatchGroup? = match?.groups?.get("a")
            return group?.value
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected MatchGroup access via MatchResult.groups to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
#endif
