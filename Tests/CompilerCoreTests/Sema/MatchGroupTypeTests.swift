#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-TYPE-007: Validates that the synthetic `kotlin.text.MatchGroup`
/// class exists in the symbol table after sema, exposes the expected
/// `value: String` and `range` properties wired to the runtime ABI link names,
/// and that source-level access through `MatchResult.groups[..]` type-checks
/// without diagnostics.
@Suite
struct MatchGroupTypeTests {
    @Test func testMatchGroup() throws {
        let source = """
        fun firstGroupValue(input: String): String? {
            val regex = Regex("(a)(b)")
            val match = regex.find(input)
            val group: MatchGroup? = match?.groups?.get("a")
            return group?.value
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected MatchGroup access via MatchResult.groups to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let classFQ = ["kotlin", "text", "MatchGroup"].map { interner.intern($0) }
        let classSymbol = try #require(
            sema.symbols.lookup(fqName: classFQ),
            "kotlin.text.MatchGroup class symbol must be registered by sema"
        )
        let classInfo = try #require(sema.symbols.symbol(classSymbol))
        #expect(classInfo.kind == .class,
                       "MatchGroup should be registered with kind=class")

        let valueFQ = ["kotlin", "text", "MatchGroup", "value"].map { interner.intern($0) }
        let valueSymbol = try #require(
            sema.symbols.lookup(fqName: valueFQ),
            "MatchGroup.value property must be registered"
        )
        let valueInfo = try #require(sema.symbols.symbol(valueSymbol))
        #expect(valueInfo.kind == .property,
                       "MatchGroup.value should be a property")
        #expect(
            sema.symbols.externalLinkName(for: valueSymbol) == "kk_match_group_value",
            "MatchGroup.value must be wired to the kk_match_group_value runtime entry"
        )

        let rangeFQ = ["kotlin", "text", "MatchGroup", "range"].map { interner.intern($0) }
        let rangeSymbol = try #require(
            sema.symbols.lookup(fqName: rangeFQ),
            "MatchGroup.range property must be registered"
        )
        let rangeInfo = try #require(sema.symbols.symbol(rangeSymbol))
        #expect(rangeInfo.kind == .property,
                       "MatchGroup.range should be a property")
        #expect(
            sema.symbols.externalLinkName(for: rangeSymbol) == "kk_match_group_range",
            "MatchGroup.range must be wired to the kk_match_group_range runtime entry"
        )
    }
}
#endif
