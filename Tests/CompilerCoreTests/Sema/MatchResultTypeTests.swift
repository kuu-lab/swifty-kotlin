#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-TYPE-010 / KSP-486: Validates that `kotlin.text.MatchResult` and
/// its nested `MatchResult.Destructured` class are correctly registered in the
/// symbol table after sema. The members are implemented in bundled Kotlin
/// (`kotlin.text.MatchResult`), so they carry no synthetic runtime link name.
@Suite
struct MatchResultTypeTests {

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

    // MARK: - 1. MatchResult class symbol

    @Test func testMatchResultClassSymbolIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchResult"].map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookup(fqName: fq),
            "kotlin.text.MatchResult class symbol must be registered by sema"
        )
        let info = try #require(sema.symbols.symbol(sym))
        #expect(info.kind == .class,
                       "MatchResult should be registered with kind=class")
    }

    // MARK: - 2. MatchResult.value: String

    @Test func testMatchResultValuePropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchResult", "value"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "MatchResult.value property must be registered")
        let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
        #expect(links.isEmpty, "MatchResult.value must be source-backed; found: \(links)")
    }

    // MARK: - 3. MatchResult.range: IntRange

    @Test func testMatchResultRangePropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchResult", "range"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "MatchResult.range property must be registered")
        let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
        #expect(links.isEmpty, "MatchResult.range must be source-backed; found: \(links)")
    }

    // MARK: - 4. MatchResult.groupValues: List<String>

    @Test func testMatchResultGroupValuesPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchResult", "groupValues"].map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookup(fqName: fq),
            "MatchResult.groupValues property must be registered"
        )
        #expect(
            sema.symbols.externalLinkName(for: sym) == nil,
            "MatchResult.groupValues must be source-backed"
        )
    }

    // MARK: - 5. MatchResult.groups: MatchGroupCollection

    @Test func testMatchResultGroupsPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchResult", "groups"].map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookup(fqName: fq),
            "MatchResult.groups property must be registered"
        )
        #expect(
            sema.symbols.externalLinkName(for: sym) == nil,
            "MatchResult.groups must be source-backed"
        )
    }

    // MARK: - 6. MatchResult.next(): MatchResult?

    @Test func testMatchResultNextFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchResult", "next"].map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookup(fqName: fq),
            "MatchResult.next() function must be registered"
        )
        #expect(
            sema.symbols.externalLinkName(for: sym) == nil,
            "MatchResult.next() must be source-backed"
        )
    }

    // MARK: - 7. MatchResult.destructured: MatchResult.Destructured

    @Test func testMatchResultDestructuredPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchResult", "destructured"].map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookup(fqName: fq),
            "MatchResult.destructured property must be registered"
        )
        #expect(
            sema.symbols.externalLinkName(for: sym) == nil,
            "MatchResult.destructured must be source-backed"
        )
    }

    // MARK: - 8. MatchResult.Destructured nested class

    @Test func testMatchResultDestructuredClassSymbolIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchResult", "Destructured"].map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookup(fqName: fq),
            "kotlin.text.MatchResult.Destructured nested class must be registered by sema"
        )
        let info = try #require(sema.symbols.symbol(sym))
        #expect(info.kind == .class,
                       "MatchResult.Destructured should be registered with kind=class")
    }

    // MARK: - 9. MatchResult.Destructured.match: MatchResult

    @Test func testMatchResultDestructuredMatchPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchResult", "Destructured", "match"]
            .map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookup(fqName: fq),
            "MatchResult.Destructured.match property must be registered"
        )
        #expect(
            sema.symbols.externalLinkName(for: sym) == nil,
            "MatchResult.Destructured.match must be source-backed"
        )
    }

    // MARK: - 10. MatchResult.Destructured.component1()..component9()

    @Test func testMatchResultDestructuredComponentFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        for index in 1...9 {
            let fq = ["kotlin", "text", "MatchResult", "Destructured", "component\(index)"]
                .map { interner.intern($0) }
            let syms = sema.symbols.lookupAll(fqName: fq)
            #expect(
                !syms.isEmpty,
                "MatchResult.Destructured.component\(index)() must be registered"
            )
            let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
            #expect(
                links.isEmpty,
                "MatchResult.Destructured.component\(index)() must be source-backed; found: \(links)"
            )
        }
    }

    // MARK: - 11. Source-level usage: basic MatchResult access type-checks

    @Test func testBasicMatchResultAccessTypeChecks() throws {
        let ctx = makeContextFromSource("""
        fun extractFirstNumber(input: String): String? {
            val regex = Regex("(\\\\d+)")
            val match = regex.find(input)
            return match?.value
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Basic MatchResult access should type-check without errors: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - 12. Source-level usage: MatchResult.destructured access type-checks

    @Test func testDestructuredPropertyAccessTypeChecks() throws {
        let ctx = makeContextFromSource("""
        fun extractGroups(input: String): String? {
            val regex = Regex("(\\\\w+)\\\\s+(\\\\w+)")
            val match = regex.find(input)
            val d = match?.destructured
            return d?.component1()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "MatchResult.destructured access should type-check without errors: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - 13. Source-level usage: MatchResult.next() chaining type-checks

    @Test func testMatchResultNextChainingTypeChecks() throws {
        let ctx = makeContextFromSource("""
        fun allMatches(input: String): List<String> {
            val regex = Regex("\\\\d+")
            var match = regex.find(input)
            val results = mutableListOf<String>()
            while (match != null) {
                results.add(match.value)
                match = match.next()
            }
            return results
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "MatchResult.next() chaining should type-check without errors: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
#endif
