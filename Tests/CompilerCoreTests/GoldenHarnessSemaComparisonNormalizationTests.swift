#if canImport(Testing)
@testable import GoldenHarnessSupport
import Testing

@Suite("GoldenHarness.SemaComparisonNormalization")
struct GoldenHarnessSemaComparisonNormalizationTests {
    @Test
    func stripsUnusedSyntheticOverloadsBeforeComparing() {
        let expected = """
        symbol s800 kind=function fq=kotlin.text.removePrefix vis=public flags=synthetic sig=recv=String params=[String] ret=String
        symbol s802 kind=function fq=kotlin.text.removeSuffix vis=public flags=synthetic sig=recv=String params=[String] ret=String
        symbol s804 kind=function fq=kotlin.text.removeSurrounding vis=public flags=synthetic sig=recv=String params=[String] ret=String
        symbol s806 kind=function fq=kotlin.text.removeSurrounding vis=public flags=synthetic sig=recv=String params=[String,String] ret=String
        expr e3 memberCall recv=e1 callee=removePrefix args=[_:e2] type=String call=s800
        expr e23 memberCall recv=e21 callee=removeSuffix args=[_:e22] type=String call=s802
        expr e43 memberCall recv=e41 callee=removeSurrounding args=[_:e42] type=String call=s804
        expr e64 memberCall recv=e61 callee=removeSurrounding args=[_:e62,_:e63] type=String call=s806
        """

        let actual = """
        symbol s801 kind=function fq=kotlin.text.removePrefix vis=public flags=synthetic sig=recv=Class#708 params=[Class#708] ret=String
        symbol s803 kind=function fq=kotlin.text.removeSuffix vis=public flags=synthetic sig=recv=Class#708 params=[Class#708] ret=String
        symbol s805 kind=function fq=kotlin.text.removeSurrounding vis=public flags=synthetic sig=recv=Class#708 params=[Class#708] ret=String
        symbol s807 kind=function fq=kotlin.text.removeSurrounding vis=public flags=synthetic sig=recv=Class#708 params=[Class#708,Class#708] ret=String
        symbol s810 kind=function fq=kotlin.text.removePrefix vis=public flags=synthetic sig=recv=String params=[String] ret=String
        symbol s811 kind=function fq=kotlin.text.removeSuffix vis=public flags=synthetic sig=recv=String params=[String] ret=String
        symbol s812 kind=function fq=kotlin.text.removeSurrounding vis=public flags=synthetic sig=recv=String params=[String] ret=String
        symbol s813 kind=function fq=kotlin.text.removeSurrounding vis=public flags=synthetic sig=recv=String params=[String,String] ret=String
        expr e3 memberCall recv=e1 callee=removePrefix args=[_:e2] type=String call=s810
        expr e23 memberCall recv=e21 callee=removeSuffix args=[_:e22] type=String call=s811
        expr e43 memberCall recv=e41 callee=removeSurrounding args=[_:e42] type=String call=s812
        expr e64 memberCall recv=e61 callee=removeSurrounding args=[_:e62,_:e63] type=String call=s813
        """

        #expect(
            GoldenHarness.normalizedForComparison(suiteName: "Sema", output: actual)
                == GoldenHarness.normalizedForComparison(suiteName: "Sema", output: expected)
        )
    }

    @Test
    func keepsTransitiveSymbolDependenciesUsedBySignatures() {
        let output = """
        symbol s10 kind=class fq=sample.Box vis=public flags=synthetic
        symbol s20 kind=function fq=sample.useBox vis=public flags=synthetic sig=recv=_ params=[Class#10] ret=Unit
        symbol s30 kind=function fq=sample.unused vis=public flags=synthetic sig=recv=_ params=[String] ret=Unit
        expr e0 call callee=e1 args=[] type=Unit call=s20
        """

        let normalized = GoldenHarness.normalizedForComparison(suiteName: "Sema", output: output)

        #expect(normalized.contains("symbol s0 kind=class fq=sample.Box"))
        #expect(normalized.contains("symbol s1 kind=function fq=sample.useBox"))
        #expect(normalized.contains("params=[Class#0]"))
        #expect(normalized.contains("call=s1"))
        #expect(!normalized.contains("sample.unused"))
    }

    @Test
    func normalizesGeneratedOrdinalsAndNegativeLocalRefs() {
        let expected = """
        symbol s10 kind=function fq=sample.wrap vis=public flags=synthetic sig=recv=_ params=[Int] ret=Int
        symbol s20 kind=valueParameter fq=sample.wrap.$300.value vis=private flags=synthetic
        symbol s30 kind=local fq=__local_14.tmp vis=private flags=_ type=Int
        expr e0 name(value) type=Int ref=s20
        expr e1 name(it) type=Int ref=s-1008192
        expr e2 name(tmp) type=Int ref=s30
        """

        let actual = """
        symbol s11 kind=function fq=sample.wrap vis=public flags=synthetic sig=recv=_ params=[Int] ret=Int
        symbol s21 kind=valueParameter fq=sample.wrap.$301.value vis=private flags=synthetic
        symbol s31 kind=local fq=__local_27.tmp vis=private flags=_ type=Int
        expr e0 name(value) type=Int ref=s21
        expr e1 name(it) type=Int ref=s-1008960
        expr e2 name(tmp) type=Int ref=s31
        """

        #expect(
            GoldenHarness.normalizedForComparison(suiteName: "Sema", output: actual)
                == GoldenHarness.normalizedForComparison(suiteName: "Sema", output: expected)
        )
    }
}
#endif
