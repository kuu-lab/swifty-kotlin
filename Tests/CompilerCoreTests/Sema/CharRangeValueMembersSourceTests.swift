@testable import CompilerCore
import Testing

@Suite
struct CharRangeValueMembersSourceTests {
    @Test
    func valueMembersAreSourceBackedOverrides() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected bundled source diagnostics: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let classFQName = ["kotlin", "ranges", "CharRange"].map(interner.intern)
        let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))

        for (name, parameterCount) in [("equals", 1), ("hashCode", 0), ("toString", 0)] {
            let members = sema.symbols.lookupAll(fqName: classFQName + [interner.intern(name)])
                .filter { sema.symbols.parentSymbol(for: $0) == classSymbol }
            #expect(members.count == 1, "Expected a single CharRange.\(name) member")
            let member = try #require(members.first)
            #expect(sema.symbols.isSourceBackedSymbol(member))
            #expect(sema.symbols.externalLinkName(for: member) == nil)
            #expect(sema.symbols.functionSignature(for: member)?.parameterTypes.count == parameterCount)
            let fileID = try #require(sema.symbols.sourceFileID(for: member))
            #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/ranges/CharRange.kt")
        }
    }
}
