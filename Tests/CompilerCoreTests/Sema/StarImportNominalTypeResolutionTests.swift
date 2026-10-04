@testable import CompilerCore
import Testing

@Suite
struct StarImportNominalTypeResolutionTests {
    private let declarations = """
    package mycharset

    open class Charset {
        fun newEncoder(): Int = 7
    }

    object Charsets {
        val UTF_8: Charset = Charset()
    }
    """

    @Test
    func testStarImportedNominalTypeRetainsItsMembersAndDefaultValueIdentity() throws {
        let use = """
        package other
        import mycharset.*

        fun use(charset: Charset): Int = charset.newEncoder()
        fun encode(charset: Charset = Charsets.UTF_8): Int = charset.newEncoder()
        """
        let ctx = makeContextFromSources([declarations, use])
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let charset = try #require(sema.symbols.lookup(
            fqName: ["mycharset", "Charset"].map { interner.intern($0) }
        ))
        let otherUse = try #require(sema.symbols.lookupAll(
            fqName: ["other", "use"].map { interner.intern($0) }
        ).first)
        let useSignature = try #require(sema.symbols.functionSignature(for: otherUse))
        guard case let .classType(parameter) = sema.types.kind(of: useSignature.parameterTypes[0]) else {
            Issue.record("Expected a nominal Charset parameter")
            return
        }
        #expect(parameter.classSymbol == charset)
    }

    @Test
    func testExplicitImportWinsAgainstCompetingStarImport() throws {
        let other = """
        package competing
        class Charset
        """
        let use = """
        package other
        import mycharset.*
        import competing.Charset

        fun choose(value: Charset): Charset = value
        """
        let ctx = makeContextFromSources([declarations, other, use])
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let competing = try #require(sema.symbols.lookup(
            fqName: ["competing", "Charset"].map { interner.intern($0) }
        ))
        let choose = try #require(sema.symbols.lookupAll(
            fqName: ["other", "choose"].map { interner.intern($0) }
        ).first)
        let signature = try #require(sema.symbols.functionSignature(for: choose))
        guard case let .classType(parameter) = sema.types.kind(of: signature.parameterTypes[0]) else {
            Issue.record("Expected an explicitly imported Charset parameter")
            return
        }
        #expect(parameter.classSymbol == competing)
    }
}
