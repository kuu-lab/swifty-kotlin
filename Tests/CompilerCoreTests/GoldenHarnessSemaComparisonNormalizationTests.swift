#if canImport(Testing)
@testable import GoldenHarnessSupport
import Testing

@Suite("GoldenHarness.SemaComparisonNormalization")
struct GoldenHarnessSemaComparisonNormalizationTests {
    @Test
    func normalizesScopeOrdinalsAndLocalOrdinals() {
        let expected = """
        symbol fq=sample.wrap kind=function vis=public flags=synthetic sig=recv=_ params=[Int] ret=Int
        symbol fq=sample.wrap.$300.value kind=valueParameter vis=private flags=synthetic
        symbol fq=__local_14.tmp kind=local vis=private flags=_ type=Int
        file f13 package=sample
        expr e0 name(value) type=Int ref=sample.wrap.$300.value
        expr e1 name(it) type=Int ref=s-1008192
        expr e2 name(tmp) type=Int ref=__local_14.tmp
        """

        let actual = """
        symbol fq=sample.wrap kind=function vis=public flags=synthetic sig=recv=_ params=[Int] ret=Int
        symbol fq=sample.wrap.$301.value kind=valueParameter vis=private flags=synthetic
        symbol fq=__local_27.tmp kind=local vis=private flags=_ type=Int
        file f15 package=sample
        expr e0 name(value) type=Int ref=sample.wrap.$301.value
        expr e1 name(it) type=Int ref=s-1008960
        expr e2 name(tmp) type=Int ref=__local_27.tmp
        """

        #expect(
            GoldenHarness.normalizedForComparison(suiteName: "Sema", output: actual)
                == GoldenHarness.normalizedForComparison(suiteName: "Sema", output: expected)
        )
    }

    @Test
    func normalizesForLoopOrdinals() {
        let expected = """
        symbol fq=__for_873.element kind=local vis=private flags=_
        symbol fq=__for_910.item kind=local vis=private flags=_
        """

        let actual = """
        symbol fq=__for_999.element kind=local vis=private flags=_
        symbol fq=__for_1050.item kind=local vis=private flags=_
        """

        #expect(
            GoldenHarness.normalizedForComparison(suiteName: "Sema", output: actual)
                == GoldenHarness.normalizedForComparison(suiteName: "Sema", output: expected)
        )
    }

    @Test
    func normalizesSemaFileIDs() {
        let expected = """
        symbol fq=sample.main kind=function vis=public flags=_ sig=recv=_ params=[] ret=Unit
        file f13 package=sample
          decl sample.main fun main sym=sample.main
        """

        let actual = """
        symbol fq=sample.main kind=function vis=public flags=_ sig=recv=_ params=[] ret=Unit
        file f14 package=sample
          decl sample.main fun main sym=sample.main
        """

        #expect(
            GoldenHarness.normalizedForComparison(suiteName: "Sema", output: actual)
                == GoldenHarness.normalizedForComparison(suiteName: "Sema", output: expected)
        )
    }

    @Test
    func normalizesExpressionDisambiguatorSuffixes() {
        let expected = """
        expr e@17:15#1 call callee=e@17:15#0 args=[_:e@17:37,_:e@17:40,_:e@17:46#1] type=sample.Value
        expr e@19:22 string(no message) type=String
        expr e@17:9#6 throw value=e@17:15#1 type=Nothing
        """

        let actual = """
        expr e@17:15#3 call callee=e@17:15#2 args=[_:e@17:37,_:e@17:40,_:e@17:46#3] type=sample.Value
        expr e@19:22#1 string(no message) type=String
        expr e@17:9#8 throw value=e@17:15#3 type=Nothing
        """

        #expect(
            GoldenHarness.normalizedForComparison(suiteName: "Sema", output: actual)
                == GoldenHarness.normalizedForComparison(suiteName: "Sema", output: expected)
        )
    }

    @Test
    func normalizesObjectLiteralOrdinals() {
        let expected = """
        symbol fq=__ObjectLiteral_13_74_110 kind=class vis=private flags=synthetic
        symbol fq=__ObjectLiteral_13_74_110.value kind=property vis=public flags=synthetic type=Int
        expr e@4:17#2 objectLiteral supers=[] type=__ObjectLiteral_13_74_110
        """

        let actual = """
        symbol fq=__ObjectLiteral_14_74_110 kind=class vis=private flags=synthetic
        symbol fq=__ObjectLiteral_14_74_110.value kind=property vis=public flags=synthetic type=Int
        expr e@4:17#9 objectLiteral supers=[] type=__ObjectLiteral_14_74_110
        """

        #expect(
            GoldenHarness.normalizedForComparison(suiteName: "Sema", output: actual)
                == GoldenHarness.normalizedForComparison(suiteName: "Sema", output: expected)
        )
    }

    @Test
    func normalizesInterfaceTypeParamScopeOrdinals() {
        let expected = """
        symbol fq=sample.Holder.$iface0.T kind=typeParameter vis=private flags=_
        symbol fq=sample.Holder.get kind=function vis=public flags=_ sig=recv=sample.Holder<sample.Holder.$iface0.T> params=[] ret=sample.Holder.$iface0.T
        """

        let actual = """
        symbol fq=sample.Holder.$iface817.T kind=typeParameter vis=private flags=_
        symbol fq=sample.Holder.get kind=function vis=public flags=_ sig=recv=sample.Holder<sample.Holder.$iface817.T> params=[] ret=sample.Holder.$iface817.T
        """

        #expect(
            GoldenHarness.normalizedForComparison(suiteName: "Sema", output: actual)
                == GoldenHarness.normalizedForComparison(suiteName: "Sema", output: expected)
        )
    }

    @Test
    func normalizesSecondaryConstructorScopeOrdinalsPreservingCtorIndex() {
        // ctorIndex (the "1" right after `$sec`) is a stable source-order position, not a
        // process-local ID, so it must survive normalization unchanged; only the trailing raw
        // symbol ID renumbers.
        let normalized = GoldenHarness.normalizedForComparison(
            suiteName: "Sema",
            output: "symbol fq=sample.Widget.<init>.$sec1_999.x kind=valueParameter vis=private flags=_"
        )
        #expect(normalized == "symbol fq=sample.Widget.<init>.$sec1_0.x kind=valueParameter vis=private flags=_")
    }

    @Test
    func normalizesSecondaryConstructorScopeOrdinalsAcrossOverloads() {
        let expected = """
        symbol fq=sample.Widget.<init>.$sec0_0.name kind=valueParameter vis=private flags=_
        symbol fq=sample.Widget.<init>.$sec1_1.name kind=valueParameter vis=private flags=_
        symbol fq=sample.Widget.<init>.$sec1_1.suffix kind=valueParameter vis=private flags=_
        """

        let actual = """
        symbol fq=sample.Widget.<init>.$sec0_5001.name kind=valueParameter vis=private flags=_
        symbol fq=sample.Widget.<init>.$sec1_5002.name kind=valueParameter vis=private flags=_
        symbol fq=sample.Widget.<init>.$sec1_5002.suffix kind=valueParameter vis=private flags=_
        """

        #expect(
            GoldenHarness.normalizedForComparison(suiteName: "Sema", output: actual)
                == GoldenHarness.normalizedForComparison(suiteName: "Sema", output: expected)
        )
    }

    @Test
    func normalizesMultiValueTypeParamDiscriminatorOrdinals() {
        let normalized = GoldenHarness.normalizedForComparison(
            suiteName: "Sema",
            output: "symbol fq=sample.pkg.zip.$tp999_888.other kind=valueParameter vis=private flags=_"
        )
        #expect(normalized == "symbol fq=sample.pkg.zip.$tp0_1.other kind=valueParameter vis=private flags=_")
    }

    @Test
    func normalizesMultiValueTypeParamDiscriminatorIndependentlyFromSingleValue() {
        // The single-value ($tp<N>.) and multi-value ($tp<N>_<M>.) discriminators are disjoint
        // patterns handled by separate regexes; each keeps its own ordinal counter.
        let expected = """
        symbol fq=sample.pkg.identity.$tp0.value kind=valueParameter vis=private flags=_
        symbol fq=sample.pkg.zip.$tp0_1.a kind=valueParameter vis=private flags=_
        symbol fq=sample.pkg.zip.$tp0_1.b kind=valueParameter vis=private flags=_
        """

        let actual = """
        symbol fq=sample.pkg.identity.$tp42.value kind=valueParameter vis=private flags=_
        symbol fq=sample.pkg.zip.$tp7001_7002.a kind=valueParameter vis=private flags=_
        symbol fq=sample.pkg.zip.$tp7001_7002.b kind=valueParameter vis=private flags=_
        """

        #expect(
            GoldenHarness.normalizedForComparison(suiteName: "Sema", output: actual)
                == GoldenHarness.normalizedForComparison(suiteName: "Sema", output: expected)
        )
    }

    @Test
    func multiValueTypeParamDiscriminatorNormalizationIsIdempotent() {
        let input = "symbol fq=sample.pkg.zip3.$tp999_888_777.c kind=valueParameter vis=private flags=_"
        let normalized = GoldenHarness.normalizedForComparison(suiteName: "Sema", output: input)
        let doubleNormalized = GoldenHarness.normalizedForComparison(suiteName: "Sema", output: normalized)
        #expect(normalized == doubleNormalized)
    }

    @Test
    func normalizesImportedInlineFunctionOrdinals() {
        let normalized = GoldenHarness.normalizedForComparison(
            suiteName: "Sema",
            output: "symbol fq=__imported_inline_204981 kind=function vis=public flags=synthetic"
        )
        #expect(normalized == "symbol fq=__imported_inline_0 kind=function vis=public flags=synthetic")
    }

    @Test
    func normalizationIsIdempotent() {
        let input = """
        symbol fq=sample.Box kind=class vis=public flags=_
        symbol fq=sample.useBox kind=function vis=public flags=_ sig=recv=_ params=[sample.Box] ret=Unit
        symbol fq=sample.useBox.$0.value kind=valueParameter vis=private flags=_
        symbol fq=__local_0.tmp kind=local vis=private flags=_ type=Int
        expr e0 call callee=e1 args=[] type=Unit call=sample.useBox
        expr e1 name(it) type=Int ref=s-0
        """

        let normalized = GoldenHarness.normalizedForComparison(suiteName: "Sema", output: input)
        let doubleNormalized = GoldenHarness.normalizedForComparison(suiteName: "Sema", output: normalized)
        #expect(normalized == doubleNormalized)
    }
}
#endif
