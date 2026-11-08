#if canImport(Testing)
import Testing
@testable import Runtime

// trim/trimStart/trimEnd predicate flat bridges are bundled Kotlin source;
// their direct tests were removed. Coverage now lives in Scripts/diff_cases
// via diff_kotlinc.sh.

@Suite(.serialized)
struct RuntimeStringHOFTests {
    // KSP-410: map/mapIndexed/mapNotNull are bundled Kotlin source
    // (StringHOF.kt); their flat runtime bridges and direct tests were
    // removed. Coverage now lives in Scripts/diff_cases/string_hof.kt /
    // string_indexed_hof.kt via diff_kotlinc.sh.

    // KSP-410: partition and filter are bundled Kotlin source (StringHOF.kt);
    // their flat runtime bridges and direct tests were removed. Coverage now
    // lives in Scripts/diff_cases/string_partition.kt / string_hof.kt via
    // diff_kotlinc.sh.

    // KSP-410: filterIndexed is bundled Kotlin source (StringHOF.kt); its
    // flat runtime bridge and direct tests were removed. Coverage now lives
    // in Scripts/diff_cases/string_indexed_hof.kt via diff_kotlinc.sh.

    // KSP-410: filterNot is bundled Kotlin source (StringHOF.kt); its flat
    // runtime bridge and direct tests were removed. Coverage now lives in
    // Scripts/diff_cases/string_hof.kt via diff_kotlinc.sh.

    // KSP-405: takeWhile/dropWhile are bundled Kotlin source (StringTakeDrop.kt);
    // their runtime bridges and direct tests were removed.

    // KSP-408: indexOfFirst/indexOfLast are bundled Kotlin source (StringIndexOf.kt);
    // their runtime bridges and direct tests were removed.

    // KSP-410: firstNotNullOf/firstNotNullOfOrNull are bundled Kotlin source
    // (StringHOF.kt); their flat runtime bridges and direct tests were
    // removed. Coverage now lives in Scripts/diff_cases/string_hof.kt via
    // diff_kotlinc.sh.

    // KSP-410: sumBy/sumByDouble are bundled Kotlin source (StringHOF.kt);
    // their flat runtime bridges and direct tests were removed. Coverage now
    // lives in Scripts/diff_cases/string_sumby.kt via diff_kotlinc.sh.

    // KSP-410: reduce/reduceOrNull/reduceIndexed/reduceIndexedOrNull/
    // reduceRight/reduceRightOrNull/reduceRightIndexed/
    // reduceRightIndexedOrNull are bundled Kotlin source (StringHOF.kt);
    // their flat runtime bridges and direct tests were removed. Coverage now
    // lives in Scripts/diff_cases/string_reduce.kt via diff_kotlinc.sh.
}
#endif
