#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CharProgressionSourceShellTests {
    @Test func nominalAndCompanionAdoptBundledSourceWithoutLosingRuntimeMembers() throws {
        let ctx = makeContextFromSource(
            """
            import kotlin.ranges.CharProgression
            import kotlin.ranges.CharRange
            fun makeProgression(): CharProgression = CharProgression.fromClosedRange('a', 'g', 2)
            fun makeRange(): CharRange = 'a'..'g'
            """
        )
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Char progression and range must still resolve: \(errors)")

        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "ranges", "CharProgression"].map(ctx.interner.intern)
        let progression = try #require(sema.symbols.lookup(fqName: fqName))
        let progressionInfo = try #require(sema.symbols.symbol(progression))
        #expect(!progressionInfo.flags.contains(.synthetic))
        #expect(progressionInfo.flags.contains(.openType))
        #expect(sema.symbols.isSourceBackedSymbol(progression))

        let companionFQName = fqName + [ctx.interner.intern("Companion")]
        #expect(sema.symbols.lookupAll(fqName: companionFQName).count == 1)
        let companion = try #require(sema.symbols.companionObjectSymbol(for: progression))
        let companionInfo = try #require(sema.symbols.symbol(companion))
        #expect(!companionInfo.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(companion))

        // The staged nominal migration retains the runtime-backed member
        // surface until the KUU-519 dependency and KUU-760 are resolved.
        for member in ["first", "last", "step"] {
            let memberFQName = fqName + [ctx.interner.intern(member)]
            #expect(sema.symbols.lookupAll(fqName: memberFQName).contains {
                sema.symbols.symbol($0)?.flags.contains(.synthetic) == true
            }, "CharProgression.\(member) must keep its existing synthetic bridge")
        }
    }
}
#endif
