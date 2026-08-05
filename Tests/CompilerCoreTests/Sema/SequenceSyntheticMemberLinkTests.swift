@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SequenceSyntheticMemberLinkTests {
    // Reference example of helper usage. See SequenceSyntheticMemberLinkTests+Helper.swift.
    // New Sequence-member resolution tests should follow this short pattern instead of the
    // 30-line boilerplate used by the remaining tests in this file (which are kept verbose
    // for now to minimize this PR's diff; gradual migration is planned).
    @Test func testSequenceSyntheticMemberLinksResolutions() throws {
        let source0 = """

        fun evenValuesFilterTypeChecksInCallExpressions(): Sequence<Int> {
        val values = sequenceOf(1, 2, 3, 4)
        return values.filter { value -> value % 2 == 0 }
        }

        fun reversedValuesReversed(): Sequence<Int> {
        return sequenceOf(1, 2, 3).reversed()
        }

        fun runningTotalsRunningFold(): Sequence<Int> {
        return sequenceOf(1, 2, 3).runningFold(10) { acc, value -> acc + value }
        }

        fun reduceValuesReduceIndexed(): Int {
        val values = sequenceOf(1, 2, 3, 4)
        return values.reduceIndexed { index, acc, value -> acc + index * value }
        }

        fun reduceValuesReduce(): Int {
        val values = sequenceOf(1, 2, 3, 4)
        return values.reduce { acc, value -> acc + value }
        }

        fun expandFlatMap(): Sequence<Int> {
        val values = sequenceOf(1, 2)
        return values.flatMap { value -> listOf(value, value * 10) }
        }

        fun keepSequenceAsSequence(): Sequence<Int> {
        return sequenceOf(1, 2, 3).asSequence()
        }

        fun reduceValuesReduceOrNull(): Int? {
        val values = sequenceOf(1, 2, 3, 4)
        return values.reduceOrNull { acc, value -> acc + value }
        }

        fun reduceValuesReduceRight(): Int {
        val values = sequenceOf(1, 2, 3, 4)
        return values.reduceRight { value, acc -> value * 10 + acc }
        }

        fun firstValueFirst(): Int {
        val values = sequenceOf(1, 2, 3)
        return values.first()
        }

        fun firstValueFirstOrNull(): Int? {
        val values = sequenceOf(1, 2, 3)
        return values.firstOrNull()
        }

        fun indexedValuesFilterIndexedTypeChecksInCallExpressions(): Sequence<Int> {
        val values = sequenceOf(10, 20, 30)
        return values.filterIndexed { index, value -> index == 1 || value == 30 }
        }

        fun indexedTotalsRunningFoldIndexed(): Sequence<Int> {
        return sequenceOf(1, 2, 3).runningFoldIndexed(10) { index, acc, value ->
        acc + index + value
        }
        }

        fun intsOnlyFilterIsInstance(): Sequence<Int> {
        val values: Sequence<Any> = sequenceOf(1, "two", 3)
        return values.filterIsInstance<Int>()
        }

        fun pickLabelFirstNotNullOf(): String {
        val values = sequenceOf(1, 2, 3)
        return values.firstNotNullOf<String> { value ->
        if (value == 2) "two" else null
        }
        }

        fun pickLabelFirstNotNullOfOrNull(): String? {
        val values = sequenceOf(1, 2, 3)
        return values.firstNotNullOfOrNull<String> { value ->
        if (value == 2) "two" else null
        }
        }

        fun sortedValuesSortedWith(): Sequence<Int> {
        val values = sequenceOf(3, 1, 2)
        return values.sortedWith { a, b -> a - b }
        }

        fun firstTwoTake(): Sequence<Int> {
        val values = sequenceOf(1, 2, 3)
        return values.take(2)
        }

        fun collectValuesToList(): List<Int> {
        val values = sequenceOf(1, 2, 3)
        return values.toList()
        }

        fun collectUniqueToHashSet(): MutableSet<Int> {
        val values = sequenceOf(3, 1, 2, 1, 3)
        return values.toHashSet()
        }

        fun pickValueRandomOrNull(): Int? {
        val values = sequenceOf(7)
        return values.randomOrNull()
        }

        fun lastTwoTakeLast(): List<Int> {
        val values = sequenceOf(1, 2, 3)
        return values.takeLast(2)
        }

        fun sortedValuesSortedBy(): Sequence<String> {
        val values = sequenceOf("cc", "a", "bbb")
        return values.sortedBy { value -> value.length }
        }

        fun trailingLargeTakeLastWhile(): List<Int> {
        val values = sequenceOf(1, 3, 4, 2, 5, 6)
        return values.takeLastWhile { value -> value > 2 }
        }

        fun leadingSmallTakeWhile(): Sequence<Int> {
        val values = sequenceOf(1, 2, 3, 4, 2)
        return values.takeWhile { value -> value < 4 }
        }

        fun pickOnlySingleOrNull(): Int? {
        return sequenceOf(42).singleOrNull()
        }

        fun sortedValuesSorted(): Sequence<Int> {
        val values = sequenceOf(3, 1, 2)
        return values.sorted()
        }

        fun sortedValuesSortedDescending(): Sequence<Int> {
        val values = sequenceOf(3, 1, 2)
        return values.sortedDescending()
        }

        fun collectMutableValuesToMutableList(): MutableList<Int> {
        val values = sequenceOf(1, 2, 3)
        return values.toMutableList()
        }

        fun collectIntoDestinationToCollection(): MutableList<Int> {
        val values = sequenceOf(1, 2, 3)
        val destination = mutableListOf(0)
        return values.toCollection(destination)
        }

        fun removeValueMinusElement(): Sequence<Int> {
        val values = sequenceOf(1, 2, 3)
        return values.minusElement(2)
        }

        fun uniqueValuesDistinct(): Sequence<Int> {
        val values = sequenceOf(1, 2, 1, 3)
        return values.distinct()
        }

        fun splitValuesPartition(): Pair<List<Int>, List<Int>> {
        val values = sequenceOf(1, 2, 3, 4)
        return values.partition { value -> value % 2 == 0 }
        }

        fun appendValuePlusElement(): Sequence<Int> {
        val values = sequenceOf(1, 2, 3)
        return values.plusElement(4)
        }

        fun hasNoValuesNone(): Boolean {
        val values = emptySequence<Int>()
        return values.none()
        }

        fun hasNoEvenValuesNone(): Boolean {
        val values = sequenceOf(1, 3, 5)
        return values.none { value -> value % 2 == 0 }
        }

        fun tailValuesDrop(): Sequence<Int> {
        val values = sequenceOf(1, 2, 3, 4)
        return values.drop(2)
        }

        fun appendSequencePlus(): Sequence<Int> {
        val values = sequenceOf(1, 2)
        return values.plus(sequenceOf(3, 4))
        }

        fun appendWithOperatorPlus(): Sequence<Int> {
        val values = sequenceOf(1, 2)
        return values + sequenceOf(3, 4)
        }

        fun uniqueByParityDistinctBy(): Sequence<Int> {
        val values = sequenceOf(1, 2, 3, 4)
        return values.distinctBy { value -> value % 2 }
        }

        fun adjacentPairCountZipWithNext(): Int {
        val values = sequenceOf(1, 2, 4, 8)
        val pairs = values.zipWithNext().take(2).toList()
        val diffs = values.zipWithNext { left, right -> right - left }.take(2).toList()
        return pairs.size + diffs.size
        }

        fun tailValuesDropWhile(): Sequence<Int> {
        val values = sequenceOf(1, 2, 3, 4)
        return values.dropWhile { value -> value < 3 }
        }

        fun traceValuesOnEach(): Sequence<Int> {
        var sum = 0
        val values = sequenceOf(1, 2, 3)
        return values.onEach { value -> sum += value }
        }

        fun hasValueContains(): Boolean {
        val values = sequenceOf(1, 2, 3)
        return values.contains(2)
        }

        fun findIndexIndexOf(): Int {
        val values = sequenceOf(10, 20, 30)
        return values.indexOf(20)
        }

        fun pickOnlySingle(): Int {
        return sequenceOf(42).single()
        }

        fun traceIndexedValuesOnEachIndexed(): Sequence<Int> {
        var trace = ""
        val values = sequenceOf(10, 20, 30)
        return values.onEachIndexed { index, value -> trace += "$index:$value;" }
        }

        fun unionValuesUnion(): Set<Int> {
        val values = sequenceOf(1, 2, 3)
        return values.union(listOf(3, 4))
        }

        fun maybeSecondValueElementAtOrNull(): Int? {
        val values = sequenceOf(1, 2, 3)
        return values.elementAtOrNull(1)
        }

        fun collectSortedValuesToSortedSet(): MutableSet<Int> {
        val values = sequenceOf(3, 1, 2, 1)
        return values.toSortedSet()
        }

        fun collectValuesToSet(): Set<Int> {
        val values = sequenceOf(1, 2, 3, 2)
        return values.toSet()
        }

        fun collectMutableValuesToMutableSet(): MutableSet<Int> {
        val values = sequenceOf(1, 2, 3, 2)
        return values.toMutableSet()
        }

        fun sortedValuesSortedByDescending(): Sequence<String> {
        val values = sequenceOf("cc", "a", "bbb")
        return values.sortedByDescending { value -> value.length }
        }

        fun windowsWindowed(): Sequence<List<Int>> {
        val values = sequenceOf(1, 2, 3, 4, 5)
        val sizes = values.windowed(3, 2, true) { window -> window.size }
        return values.windowed(3, 2, true)
        }

        fun subtractValuesSubtract(): Set<Int> {
        val values = sequenceOf(1, 2, 3)
        return values.subtract(listOf(2))
        }

        fun singleUseConstrainOnce(): Sequence<Int> {
        val values = sequenceOf(1, 2, 3)
        return values.constrainOnce()
        }

        fun secondValueElementAt(): Int {
        val values = sequenceOf(1, 2, 3)
        return values.elementAt(1)
        }

        fun countValuesCount(): Int {
        val values = sequenceOf(1, 2, 3)
        return values.count()
        }

        fun removeValueMinus(): Sequence<Int> {
        val values = sequenceOf(1, 2, 3)
        return values.minus(2)
        }

        fun removeWithOperatorMinus(): Sequence<Int> {
        val values = sequenceOf(1, 2, 3)
        return values - 2
        }

        fun selectedValueElementAtOrElse(): Int {
        val values = sequenceOf(1, 2, 3)
        return values.elementAtOrElse(4) { index -> index * 10 }
        }

        fun chunkValuesChunked(): Int {
        val values = sequenceOf(1, 2, 3, 4, 5)
        val chunks = values.chunked(2)
        return chunks.toList().size
        }

        fun weightedSumOf(): Int {
        val values = sequenceOf(1, 2, 3)
        return values.sumOf { value ->
        if (value == 2) 10 else value
        }
        }

        fun totalSum(): Int {
        val values = sequenceOf(1, 2, 3)
        return values.sum()
        }

        fun largestMaxWith(): Int {
        val values = sequenceOf(1, 3, 2)
        return values.maxWith { left, right -> left - right }
        }

        fun valuesFilterNotNull(input: Sequence<Int?>): Sequence<Int> {
        return input.filterNotNull()
        }

        fun largestSelectorOrNullMaxOfOrNull(): Int? {
        val values = sequenceOf(1, 3, 2)
        return values.maxOfOrNull { value -> -value }
        }

        fun largestOrNullMaxOrNull(): Int? {
        val values = sequenceOf(1, 3, 2)
        return values.maxOrNull()
        }

        fun firstEvenFind(): Int? {
        val values = sequenceOf(1, 2, 3, 4, 5)
        return values.find { value -> value % 2 == 0 }
        }

        fun evensFilterTo(): MutableList<Int> {
        val values = sequenceOf(1, 2, 3, 4, 5)
        val destination = mutableListOf<Int>(99)
        return values.filterTo(destination) { value -> value % 2 == 0 }
        }

        fun largestOrNullMaxWithOrNull(): Int? {
        val values = sequenceOf(1, 3, 2)
        return values.maxWithOrNull { left, right -> left - right }
        }

        fun oddsFilterNot(): Sequence<Int> {
        val values = sequenceOf(1, 2, 3, 4, 5)
        return values.filterNot { value -> value % 2 == 0 }
        }

        fun oddsFilterNotTo(): MutableList<Int> {
        val values = sequenceOf(1, 2, 3, 4, 5)
        val destination = mutableListOf<Int>(99)
        return values.filterNotTo(destination) { value -> value % 2 == 0 }
        }

        fun smallestProjectionMinOf(): Int {
        val values = sequenceOf(5, 2, 3)
        return values.minOf { value -> value * 10 }
        }

        fun indexedTotalsRunningReduceIndexed() {
        val totals = sequenceOf(1, 2, 3).runningReduceIndexed { index, acc, value ->
        acc + index + value
        }
        println(totals)
        }

        fun largestSelectorMaxOf(): Int {
        val values = sequenceOf(1, 3, 2)
        return values.maxOf { value -> -value }
        }

        fun smallestMin(): Int {
        val values = sequenceOf(3, 1, 2)
        return values.min()
        }

        fun largestMax(): Int {
        val values = sequenceOf(1, 3, 2)
        return values.max()
        }

        fun smallestProjectionMinOfOrNull(): Int? {
        val values = sequenceOf(5, 2, 3)
        return values.minOfOrNull { value -> value * 10 }
        }

        fun smallestByRemainderMinBy(): Int {
        val values = sequenceOf(5, 2, 3)
        return values.minBy { value -> value % 3 }
        }

        fun indexedScanScanIndexed() {
        sequenceOf(1, 2, 3).scanIndexed(10) { index, acc, value ->
        acc + index + value
        }
        }

        fun checksumReduceRightIndexed(): Int {
        val values = sequenceOf(1, 2, 3, 4)
        return values.reduceRightIndexed { index, value, acc -> index * 100 + value * 10 + acc }
        }

        fun checksumReduceRightIndexedOrNull(): Int? {
        val values = sequenceOf(1, 2, 3, 4)
        return values.reduceRightIndexedOrNull { index, value, acc -> index * 100 + value * 10 + acc }
        }

        fun checksumReduceRightOrNull(): Int? {
        val values = sequenceOf(1, 2, 3, 4)
        return values.reduceRightOrNull { value, acc -> value * 10 + acc }
        }

        fun scannedScan(): Sequence<Int> {
        return sequenceOf(1, 2, 3).scan(10) { acc, value ->
        acc + value
        }
        }

        fun checkedRequireNoNullsResolvesNullableReceiverInCallExpressions(values: Sequence<Int?>) {
        val result = values.requireNoNulls()
        println(result.toList())
        }

        fun largestByNegativeMaxBy(): Int {
        val values = sequenceOf(1, 3, 2)
        return values.maxBy { value -> -value }
        }

        fun largestByNegativeOrNullMaxByOrNull(): Int? {
        val values = sequenceOf(1, 3, 2)
        return values.maxByOrNull { value -> -value }
        }

        fun smallestByRemainderMinByOrNull(): Int? {
        val values = sequenceOf(5, 2, 3)
        return values.minByOrNull { value -> value % 3 }
        }

        """

        let source1 = """

        fun pickValue(): Int { return sequenceOf(7).random() }
        fun indexedValuesSize(): Int {
            val values = sequenceOf(10, 20, 30)
            return values.withIndex().toList().size
        }
        fun weightedDouble(): Int {
            val values = sequenceOf(1, 2, 3)
            return values.sumBy { value ->
                if (value == 2) 10 else value
            }
        }
        fun weighted(): Double {
            val values = sequenceOf(1, 2, 3)
            return values.sumByDouble { value ->
                if (value == 2) 1.5 else 0.25
            }
        }
        fun smallestByReverseOrderOrNull(): Int? {
            val values = sequenceOf(5, 2, 3)
            return values.minWithOrNull(reverseOrder<Int>())
        }
        fun collectInts(): MutableList<Int> {
            val values: Sequence<Any> = sequenceOf(1, "two", 3)
            val dest = mutableListOf<Int>(0)
            return values.filterIsInstanceTo(dest)
        }
        fun smallest(): Int? {
            val values = sequenceOf(5, 2, 3)
            return values.minOrNull()
        }
        fun smallestByReverseOrder(): Int {
            val values = sequenceOf(5, 2, 3)
            return values.minWith(reverseOrder<Int>())
        }

        """

        try withTemporaryFiles(contents: [source0, source1]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected combined Sequence member sources to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

        // testSequenceFilterTypeChecksInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceReversedResolvesInCallExpressions -> Sequence.reversed
            let memberFQNameReversed = ["kotlin", "sequences", "Sequence", "reversed"].map { ctx.interner.intern($0) }
            let linksReversed = Set(
                sema.symbols.lookupAll(fqName: memberFQNameReversed).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksReversed.contains("kk_sequence_reversed"),
                "Expected Sequence.reversed to link to kk_sequence_reversed, got \(linksReversed.sorted())"
            )
        }

        do {
            // testSequenceRunningFoldResolvesInCallExpressions -> Sequence.runningFold
            let memberFQNameRunningFold = ["kotlin", "sequences", "Sequence", "runningFold"].map { ctx.interner.intern($0) }
            let linksRunningFold = Set(
                sema.symbols.lookupAll(fqName: memberFQNameRunningFold).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksRunningFold.contains("kk_sequence_runningFold"),
                "Expected Sequence.runningFold to link to kk_sequence_runningFold, got \(linksRunningFold.sorted())"
            )
        }

        do {
            // testSequenceReduceIndexedResolvesInCallExpressions -> Sequence.reduceIndexed
            let memberFQNameReduceIndexed = ["kotlin", "sequences", "Sequence", "reduceIndexed"].map { ctx.interner.intern($0) }
            let linksReduceIndexed = Set(
                sema.symbols.lookupAll(fqName: memberFQNameReduceIndexed).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksReduceIndexed.contains("kk_sequence_reduceIndexed"),
                "Expected Sequence.reduceIndexed to link to kk_sequence_reduceIndexed, got \(linksReduceIndexed.sorted())"
            )
        }

        // testSequenceReduceResolvesInCallExpressions -> no additional link assertion (source only)

        // testSequenceFlatMapResolvesInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceAsSequenceResolvesInCallExpressions -> Sequence.asSequence
            let memberFQNameAsSequence = ["kotlin", "sequences", "Sequence", "asSequence"].map { ctx.interner.intern($0) }
            let linksAsSequence = Set(
                sema.symbols.lookupAll(fqName: memberFQNameAsSequence).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksAsSequence.contains("kk_sequence_asSequence"),
                "Expected Sequence.asSequence to link to kk_sequence_asSequence, got \(linksAsSequence.sorted())"
            )
        }

        do {
            // testSequenceReduceOrNullResolvesInCallExpressions -> Sequence.reduceOrNull
            let memberFQNameReduceOrNull = ["kotlin", "sequences", "Sequence", "reduceOrNull"].map { ctx.interner.intern($0) }
            let linksReduceOrNull = Set(
                sema.symbols.lookupAll(fqName: memberFQNameReduceOrNull).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksReduceOrNull.contains("kk_sequence_reduceOrNull"),
                "Expected Sequence.reduceOrNull to link to kk_sequence_reduceOrNull, got \(linksReduceOrNull.sorted())"
            )
        }

        do {
            // testSequenceReduceRightResolvesInCallExpressions -> Sequence.reduceRight
            let memberFQNameReduceRight = ["kotlin", "sequences", "Sequence", "reduceRight"].map { ctx.interner.intern($0) }
            let linksReduceRight = Set(
                sema.symbols.lookupAll(fqName: memberFQNameReduceRight).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksReduceRight.contains("kk_sequence_reduceRight"),
                "Expected Sequence.reduceRight to link to kk_sequence_reduceRight, got \(linksReduceRight.sorted())"
            )
        }

        do {
            // testSequenceFirstResolvesInCallExpressions -> Sequence.first
            let memberFQNameFirst = ["kotlin", "sequences", "Sequence", "first"].map { ctx.interner.intern($0) }
            let linksFirst = Set(
                sema.symbols.lookupAll(fqName: memberFQNameFirst).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksFirst.contains("kk_sequence_first"),
                "Expected Sequence.first to link to kk_sequence_first, got \(linksFirst.sorted())"
            )
        }

        do {
            // testSequenceFirstOrNullResolvesInCallExpressions -> Sequence.firstOrNull
            let memberFQNameFirstOrNull = ["kotlin", "sequences", "Sequence", "firstOrNull"].map { ctx.interner.intern($0) }
            let linksFirstOrNull = Set(
                sema.symbols.lookupAll(fqName: memberFQNameFirstOrNull).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksFirstOrNull.contains("kk_sequence_firstOrNull"),
                "Expected Sequence.firstOrNull to link to kk_sequence_firstOrNull, got \(linksFirstOrNull.sorted())"
            )
        }

        // testSequenceFilterIndexedTypeChecksInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceRunningFoldIndexedResolvesInCallExpressions -> Sequence.runningFoldIndexed
            let memberFQNameRunningFoldIndexed = ["kotlin", "sequences", "Sequence", "runningFoldIndexed"].map { ctx.interner.intern($0) }
            let linksRunningFoldIndexed = Set(
                sema.symbols.lookupAll(fqName: memberFQNameRunningFoldIndexed).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksRunningFoldIndexed.contains("kk_sequence_runningFoldIndexed"),
                "Expected Sequence.runningFoldIndexed to link to kk_sequence_runningFoldIndexed, got \(linksRunningFoldIndexed.sorted())"
            )
        }

        do {
            // testSequenceFilterIsInstanceResolvesInCallExpressions -> Sequence.filterIsInstance
            let memberFQNameFilterIsInstance = ["kotlin", "sequences", "Sequence", "filterIsInstance"].map { ctx.interner.intern($0) }
            let linksFilterIsInstance = Set(
                sema.symbols.lookupAll(fqName: memberFQNameFilterIsInstance).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksFilterIsInstance.contains("kk_sequence_filterIsInstance"),
                "Expected Sequence.filterIsInstance to link to kk_sequence_filterIsInstance, got \(linksFilterIsInstance.sorted())"
            )
        }

        do {
            // testSequenceFirstNotNullOfResolvesInCallExpressions -> Sequence.firstNotNullOf
            let memberFQNameFirstNotNullOf = ["kotlin", "sequences", "Sequence", "firstNotNullOf"].map { ctx.interner.intern($0) }
            let linksFirstNotNullOf = Set(
                sema.symbols.lookupAll(fqName: memberFQNameFirstNotNullOf).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksFirstNotNullOf.contains("kk_sequence_firstNotNullOf"),
                "Expected Sequence.firstNotNullOf to link to kk_sequence_firstNotNullOf, got \(linksFirstNotNullOf.sorted())"
            )
        }

        do {
            // testSequenceFirstNotNullOfOrNullResolvesInCallExpressions -> Sequence.firstNotNullOfOrNull
            let memberFQNameFirstNotNullOfOrNull = ["kotlin", "sequences", "Sequence", "firstNotNullOfOrNull"].map { ctx.interner.intern($0) }
            let linksFirstNotNullOfOrNull = Set(
                sema.symbols.lookupAll(fqName: memberFQNameFirstNotNullOfOrNull).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksFirstNotNullOfOrNull.contains("kk_sequence_firstNotNullOfOrNull"),
                "Expected Sequence.firstNotNullOfOrNull to link to kk_sequence_firstNotNullOfOrNull, got \(linksFirstNotNullOfOrNull.sorted())"
            )
        }

        do {
            // testSequenceSortedWithResolvesInCallExpressions -> Sequence.sortedWith
            let memberFQNameSortedWith = ["kotlin", "sequences", "Sequence", "sortedWith"].map { ctx.interner.intern($0) }
            let linksSortedWith = Set(
                sema.symbols.lookupAll(fqName: memberFQNameSortedWith).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksSortedWith.contains("kk_sequence_sortedWith"),
                "Expected Sequence.sortedWith to link to kk_sequence_sortedWith, got \(linksSortedWith.sorted())"
            )
        }

        // testSequenceTakeResolvesInCallExpressions -> no additional link assertion (source only)

        // testSequenceToListResolvesInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceToHashSetResolvesInCallExpressions -> Sequence.toHashSet
            let memberFQNameToHashSet = ["kotlin", "sequences", "Sequence", "toHashSet"].map { ctx.interner.intern($0) }
            let linksToHashSet = Set(
                sema.symbols.lookupAll(fqName: memberFQNameToHashSet).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksToHashSet.contains("kk_sequence_toHashSet"),
                "Expected Sequence.toHashSet to link to kk_sequence_toHashSet, got \(linksToHashSet.sorted())"
            )
        }

        do {
            // testSequenceRandomOrNullResolvesInCallExpressions -> Sequence.randomOrNull
            let memberFQNameRandomOrNull = ["kotlin", "sequences", "Sequence", "randomOrNull"].map { ctx.interner.intern($0) }
            let linksRandomOrNull = Set(
                sema.symbols.lookupAll(fqName: memberFQNameRandomOrNull).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksRandomOrNull.contains("kk_sequence_randomOrNull"),
                "Expected Sequence.randomOrNull to link to kk_sequence_randomOrNull, got \(linksRandomOrNull.sorted())"
            )
        }

        do {
            // testSequenceTakeLastResolvesInCallExpressions -> Sequence.takeLast
            let memberFQNameTakeLast = ["kotlin", "sequences", "Sequence", "takeLast"].map { ctx.interner.intern($0) }
            let linksTakeLast = Set(
                sema.symbols.lookupAll(fqName: memberFQNameTakeLast).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksTakeLast.contains("kk_sequence_takeLast"),
                "Expected Sequence.takeLast to link to kk_sequence_takeLast, got \(linksTakeLast.sorted())"
            )
        }

        do {
            // testSequenceSortedByResolvesInCallExpressions -> Sequence.sortedBy
            let memberFQNameSortedBy = ["kotlin", "sequences", "Sequence", "sortedBy"].map { ctx.interner.intern($0) }
            let linksSortedBy = Set(
                sema.symbols.lookupAll(fqName: memberFQNameSortedBy).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksSortedBy.contains("kk_sequence_sortedBy"),
                "Expected Sequence.sortedBy to link to kk_sequence_sortedBy, got \(linksSortedBy.sorted())"
            )
        }

        do {
            // testSequenceTakeLastWhileResolvesInCallExpressions -> Sequence.takeLastWhile
            let memberFQNameTakeLastWhile = ["kotlin", "sequences", "Sequence", "takeLastWhile"].map { ctx.interner.intern($0) }
            let linksTakeLastWhile = Set(
                sema.symbols.lookupAll(fqName: memberFQNameTakeLastWhile).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksTakeLastWhile.contains("kk_sequence_takeLastWhile"),
                "Expected Sequence.takeLastWhile to link to kk_sequence_takeLastWhile, got \(linksTakeLastWhile.sorted())"
            )
        }

        // testSequenceTakeWhileResolvesInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceSingleOrNullResolvesInCallExpressions -> Sequence.singleOrNull
            let memberFQNameSingleOrNull = ["kotlin", "sequences", "Sequence", "singleOrNull"].map { ctx.interner.intern($0) }
            let linksSingleOrNull = Set(
                sema.symbols.lookupAll(fqName: memberFQNameSingleOrNull).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksSingleOrNull.contains("kk_sequence_singleOrNull"),
                "Expected Sequence.singleOrNull to link to kk_sequence_singleOrNull, got \(linksSingleOrNull.sorted())"
            )
        }

        do {
            // testSequenceSortedResolvesInCallExpressions -> Sequence.sorted
            let memberFQNameSorted = ["kotlin", "sequences", "Sequence", "sorted"].map { ctx.interner.intern($0) }
            let linksSorted = Set(
                sema.symbols.lookupAll(fqName: memberFQNameSorted).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksSorted.contains("kk_sequence_sorted"),
                "Expected Sequence.sorted to link to kk_sequence_sorted, got \(linksSorted.sorted())"
            )
        }

        do {
            // testSequenceSortedDescendingResolvesInCallExpressions -> Sequence.sortedDescending
            let memberFQNameSortedDescending = ["kotlin", "sequences", "Sequence", "sortedDescending"].map { ctx.interner.intern($0) }
            let linksSortedDescending = Set(
                sema.symbols.lookupAll(fqName: memberFQNameSortedDescending).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksSortedDescending.contains("kk_sequence_sortedDescending"),
                "Expected Sequence.sortedDescending to link to kk_sequence_sortedDescending, got \(linksSortedDescending.sorted())"
            )
        }

        // testSequenceToMutableListResolvesInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceToCollectionResolvesInCallExpressions -> Sequence.toCollection
            let memberFQNameToCollection = ["kotlin", "sequences", "Sequence", "toCollection"].map { ctx.interner.intern($0) }
            let linksToCollection = Set(
                sema.symbols.lookupAll(fqName: memberFQNameToCollection).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksToCollection.contains("kk_sequence_toCollection"),
                "Expected Sequence.toCollection to link to kk_sequence_toCollection, got \(linksToCollection.sorted())"
            )
        }

        do {
            // testSequenceMinusElementResolvesInCallExpressions -> Sequence.minusElement
            let memberFQNameMinusElement = ["kotlin", "sequences", "Sequence", "minusElement"].map { ctx.interner.intern($0) }
            let linksMinusElement = Set(
                sema.symbols.lookupAll(fqName: memberFQNameMinusElement).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksMinusElement.contains("kk_sequence_minus"),
                "Expected Sequence.minusElement to link to kk_sequence_minus, got \(linksMinusElement.sorted())"
            )
        }

        // testSequenceDistinctResolvesInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequencePartitionResolvesInCallExpressions -> Sequence.partition
            let memberFQNamePartition = ["kotlin", "sequences", "Sequence", "partition"].map { ctx.interner.intern($0) }
            let linksPartition = Set(
                sema.symbols.lookupAll(fqName: memberFQNamePartition).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksPartition.contains("kk_sequence_partition"),
                "Expected Sequence.partition to link to kk_sequence_partition, got \(linksPartition.sorted())"
            )
        }

        do {
            // testSequencePlusElementResolvesInCallExpressions -> Sequence.plusElement
            let memberFQNamePlusElement = ["kotlin", "sequences", "Sequence", "plusElement"].map { ctx.interner.intern($0) }
            let linksPlusElement = Set(
                sema.symbols.lookupAll(fqName: memberFQNamePlusElement).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksPlusElement.contains("kk_sequence_plus_element"),
                "Expected Sequence.plusElement to link to kk_sequence_plus_element, got \(linksPlusElement.sorted())"
            )
        }

        do {
            // testSequenceNoneResolvesInCallExpressions -> Sequence.none
            let memberFQNameNone = ["kotlin", "sequences", "Sequence", "none"].map { ctx.interner.intern($0) }
            let linksNone = Set(
                sema.symbols.lookupAll(fqName: memberFQNameNone).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksNone.contains("kk_sequence_none"),
                "Expected Sequence.none to link to kk_sequence_none, got \(linksNone.sorted())"
            )
        }

        // testSequenceDropResolvesInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequencePlusResolvesInCallExpressions -> Sequence.plus
            let memberFQNamePlus = ["kotlin", "sequences", "Sequence", "plus"].map { ctx.interner.intern($0) }
            let linksPlus = Set(
                sema.symbols.lookupAll(fqName: memberFQNamePlus).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksPlus.contains("kk_sequence_plus"),
                "Expected Sequence.plus to link to kk_sequence_plus, got \(linksPlus.sorted())"
            )
        }

        // testSequenceDistinctByResolvesInCallExpressions -> no additional link assertion (source only)

        // testSequenceZipWithNextResolvesInCallExpressions -> no additional link assertion (source only)

        // testSequenceDropWhileResolvesInCallExpressions -> no additional link assertion (source only)

        // testSequenceOnEachResolvesInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceContainsResolvesInCallExpressions -> Sequence.contains
            let memberFQNameContains = ["kotlin", "sequences", "Sequence", "contains"].map { ctx.interner.intern($0) }
            let linksContains = Set(
                sema.symbols.lookupAll(fqName: memberFQNameContains).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksContains.contains("kk_sequence_contains"),
                "Expected Sequence.contains to link to kk_sequence_contains, got \(linksContains.sorted())"
            )
        }

        // testSequenceIndexOfResolvesInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceSingleResolvesInCallExpressions -> Sequence.single
            let memberFQNameSingle = ["kotlin", "sequences", "Sequence", "single"].map { ctx.interner.intern($0) }
            let linksSingle = Set(
                sema.symbols.lookupAll(fqName: memberFQNameSingle).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksSingle.contains("kk_sequence_single"),
                "Expected Sequence.single to link to kk_sequence_single, got \(linksSingle.sorted())"
            )
        }

        // testSequenceOnEachIndexedResolvesInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceUnionResolvesInCallExpressions -> Sequence.union
            let memberFQNameUnion = ["kotlin", "sequences", "Sequence", "union"].map { ctx.interner.intern($0) }
            let linksUnion = Set(
                sema.symbols.lookupAll(fqName: memberFQNameUnion).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksUnion.contains("kk_sequence_union"),
                "Expected Sequence.union to link to kk_sequence_union, got \(linksUnion.sorted())"
            )
        }

        do {
            // testSequenceElementAtOrNullResolvesInCallExpressions -> Sequence.elementAtOrNull
            let memberFQNameElementAtOrNull = ["kotlin", "sequences", "Sequence", "elementAtOrNull"].map { ctx.interner.intern($0) }
            let linksElementAtOrNull = Set(
                sema.symbols.lookupAll(fqName: memberFQNameElementAtOrNull).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksElementAtOrNull.contains("kk_sequence_elementAtOrNull"),
                "Expected Sequence.elementAtOrNull to link to kk_sequence_elementAtOrNull, got \(linksElementAtOrNull.sorted())"
            )
        }

        do {
            // testSequenceToSortedSetResolvesInCallExpressions -> Sequence.toSortedSet
            let memberFQNameToSortedSet = ["kotlin", "sequences", "Sequence", "toSortedSet"].map { ctx.interner.intern($0) }
            let linksToSortedSet = Set(
                sema.symbols.lookupAll(fqName: memberFQNameToSortedSet).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksToSortedSet.contains("kk_sequence_toSortedSet"),
                "Expected Sequence.toSortedSet to link to kk_sequence_toSortedSet, got \(linksToSortedSet.sorted())"
            )
        }

        // testSequenceToSetResolvesInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceToMutableSetResolvesInCallExpressions -> Sequence.toMutableSet
            let memberFQNameToMutableSet = ["kotlin", "sequences", "Sequence", "toMutableSet"].map { ctx.interner.intern($0) }
            let linksToMutableSet = Set(
                sema.symbols.lookupAll(fqName: memberFQNameToMutableSet).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksToMutableSet.contains("kk_sequence_toMutableSet"),
                "Expected Sequence.toMutableSet to link to kk_sequence_toMutableSet, got \(linksToMutableSet.sorted())"
            )
        }

        do {
            // testSequenceSortedByDescendingResolvesInCallExpressions -> Sequence.sortedByDescending
            let memberFQNameSortedByDescending = ["kotlin", "sequences", "Sequence", "sortedByDescending"].map { ctx.interner.intern($0) }
            let linksSortedByDescending = Set(
                sema.symbols.lookupAll(fqName: memberFQNameSortedByDescending).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksSortedByDescending.contains("kk_sequence_sortedByDescending"),
                "Expected Sequence.sortedByDescending to link to kk_sequence_sortedByDescending, got \(linksSortedByDescending.sorted())"
            )
        }

        // testSequenceWindowedResolvesInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceSubtractResolvesInCallExpressions -> Sequence.subtract
            let memberFQNameSubtract = ["kotlin", "sequences", "Sequence", "subtract"].map { ctx.interner.intern($0) }
            let linksSubtract = Set(
                sema.symbols.lookupAll(fqName: memberFQNameSubtract).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksSubtract.contains("kk_sequence_subtract"),
                "Expected Sequence.subtract to link to kk_sequence_subtract, got \(linksSubtract.sorted())"
            )
        }

        do {
            // testSequenceConstrainOnceResolvesInCallExpressions -> Sequence.constrainOnce
            let memberFQNameConstrainOnce = ["kotlin", "sequences", "Sequence", "constrainOnce"].map { ctx.interner.intern($0) }
            let linksConstrainOnce = Set(
                sema.symbols.lookupAll(fqName: memberFQNameConstrainOnce).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksConstrainOnce.contains("kk_sequence_constrainOnce"),
                "Expected Sequence.constrainOnce to link to kk_sequence_constrainOnce, got \(linksConstrainOnce.sorted())"
            )
        }

        do {
            // testSequenceElementAtResolvesInCallExpressions -> Sequence.elementAt
            let memberFQNameElementAt = ["kotlin", "sequences", "Sequence", "elementAt"].map { ctx.interner.intern($0) }
            let linksElementAt = Set(
                sema.symbols.lookupAll(fqName: memberFQNameElementAt).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksElementAt.contains("kk_sequence_elementAt"),
                "Expected Sequence.elementAt to link to kk_sequence_elementAt, got \(linksElementAt.sorted())"
            )
        }

        do {
            // testSequenceCountResolvesInCallExpressions -> Sequence.count
            let memberFQNameCount = ["kotlin", "sequences", "Sequence", "count"].map { ctx.interner.intern($0) }
            let linksCount = Set(
                sema.symbols.lookupAll(fqName: memberFQNameCount).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksCount.contains("kk_sequence_count"),
                "Expected Sequence.count to link to kk_sequence_count, got \(linksCount.sorted())"
            )
        }

        do {
            // testSequenceMinusResolvesInCallExpressions -> Sequence.minus
            let memberFQNameMinus = ["kotlin", "sequences", "Sequence", "minus"].map { ctx.interner.intern($0) }
            let linksMinus = Set(
                sema.symbols.lookupAll(fqName: memberFQNameMinus).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksMinus.contains("kk_sequence_minus"),
                "Expected Sequence.minus to link to kk_sequence_minus, got \(linksMinus.sorted())"
            )
        }

        do {
            // testSequenceElementAtOrElseResolvesInCallExpressions -> Sequence.elementAtOrElse
            let memberFQNameElementAtOrElse = ["kotlin", "sequences", "Sequence", "elementAtOrElse"].map { ctx.interner.intern($0) }
            let linksElementAtOrElse = Set(
                sema.symbols.lookupAll(fqName: memberFQNameElementAtOrElse).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksElementAtOrElse.contains("kk_sequence_elementAtOrElse"),
                "Expected Sequence.elementAtOrElse to link to kk_sequence_elementAtOrElse, got \(linksElementAtOrElse.sorted())"
            )
        }

        // testSequenceChunkedResolvesInCallExpressions -> no additional link assertion (source only)

        // testSequenceSumOfResolvesInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceSumResolvesInCallExpressions -> Sequence.sum
            let memberFQNameSum = ["kotlin", "sequences", "Sequence", "sum"].map { ctx.interner.intern($0) }
            let linksSum = Set(
                sema.symbols.lookupAll(fqName: memberFQNameSum).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksSum.contains("kk_sequence_sum"),
                "Expected Sequence.sum to link to kk_sequence_sum, got \(linksSum.sorted())"
            )
        }

        do {
            // testSequenceMaxWithResolvesInCallExpressions -> Sequence.maxWith
            let memberFQNameMaxWith = ["kotlin", "sequences", "Sequence", "maxWith"].map { ctx.interner.intern($0) }
            let linksMaxWith = Set(
                sema.symbols.lookupAll(fqName: memberFQNameMaxWith).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksMaxWith.contains("kk_sequence_maxWith"),
                "Expected Sequence.maxWith to link to kk_sequence_maxWith, got \(linksMaxWith.sorted())"
            )
        }

        // testSequenceFilterNotNullResolvesInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceMaxOfOrNullResolvesInCallExpressions -> Sequence.maxOfOrNull
            let memberFQNameMaxOfOrNull = ["kotlin", "sequences", "Sequence", "maxOfOrNull"].map { ctx.interner.intern($0) }
            let linksMaxOfOrNull = Set(
                sema.symbols.lookupAll(fqName: memberFQNameMaxOfOrNull).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksMaxOfOrNull.contains("kk_sequence_maxOfOrNull"),
                "Expected Sequence.maxOfOrNull to link to kk_sequence_maxOfOrNull, got \(linksMaxOfOrNull.sorted())"
            )
        }

        do {
            // testSequenceMaxOrNullResolvesWithNullableElementReturnType -> Sequence.maxOrNull
            let memberFQNameMaxOrNull = ["kotlin", "sequences", "Sequence", "maxOrNull"].map { ctx.interner.intern($0) }
            let linksMaxOrNull = Set(
                sema.symbols.lookupAll(fqName: memberFQNameMaxOrNull).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksMaxOrNull.contains("kk_sequence_maxOrNull"),
                "Expected Sequence.maxOrNull to link to kk_sequence_maxOrNull, got \(linksMaxOrNull.sorted())"
            )
        }

        do {
            // testSequenceFindResolvesInCallExpressions -> Sequence.find
            let memberFQNameFind = ["kotlin", "sequences", "Sequence", "find"].map { ctx.interner.intern($0) }
            let linksFind = Set(
                sema.symbols.lookupAll(fqName: memberFQNameFind).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksFind.contains("kk_sequence_find"),
                "Expected Sequence.find to link to kk_sequence_find, got \(linksFind.sorted())"
            )
        }

        do {
            // testSequenceFilterToResolvesInCallExpressions -> Sequence.filterTo
            let memberFQNameFilterTo = ["kotlin", "sequences", "Sequence", "filterTo"].map { ctx.interner.intern($0) }
            let linksFilterTo = Set(
                sema.symbols.lookupAll(fqName: memberFQNameFilterTo).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksFilterTo.contains("kk_sequence_filterTo"),
                "Expected Sequence.filterTo to link to kk_sequence_filterTo, got \(linksFilterTo.sorted())"
            )
        }

        do {
            // testSequenceMaxWithOrNullResolvesInCallExpressions -> Sequence.maxWithOrNull
            let memberFQNameMaxWithOrNull = ["kotlin", "sequences", "Sequence", "maxWithOrNull"].map { ctx.interner.intern($0) }
            let linksMaxWithOrNull = Set(
                sema.symbols.lookupAll(fqName: memberFQNameMaxWithOrNull).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksMaxWithOrNull.contains("kk_sequence_maxWithOrNull"),
                "Expected Sequence.maxWithOrNull to link to kk_sequence_maxWithOrNull, got \(linksMaxWithOrNull.sorted())"
            )
        }

        // testSequenceFilterNotResolvesInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceFilterNotToResolvesInCallExpressions -> Sequence.filterNotTo
            let memberFQNameFilterNotTo = ["kotlin", "sequences", "Sequence", "filterNotTo"].map { ctx.interner.intern($0) }
            let linksFilterNotTo = Set(
                sema.symbols.lookupAll(fqName: memberFQNameFilterNotTo).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksFilterNotTo.contains("kk_sequence_filterNotTo"),
                "Expected Sequence.filterNotTo to link to kk_sequence_filterNotTo, got \(linksFilterNotTo.sorted())"
            )
        }

        do {
            // testSequenceMinOfResolvesInCallExpressions -> Sequence.minOf
            let memberFQNameMinOf = ["kotlin", "sequences", "Sequence", "minOf"].map { ctx.interner.intern($0) }
            let linksMinOf = Set(
                sema.symbols.lookupAll(fqName: memberFQNameMinOf).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksMinOf.contains("kk_sequence_minOf"),
                "Expected Sequence.minOf to link to kk_sequence_minOf, got \(linksMinOf.sorted())"
            )
        }

        do {
            // testSequenceRunningReduceIndexedResolvesInCallExpressions -> Sequence.runningReduceIndexed
            let memberFQNameRunningReduceIndexed = ["kotlin", "sequences", "Sequence", "runningReduceIndexed"].map { ctx.interner.intern($0) }
            let linksRunningReduceIndexed = Set(
                sema.symbols.lookupAll(fqName: memberFQNameRunningReduceIndexed).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksRunningReduceIndexed.contains("kk_sequence_runningReduceIndexed"),
                "Expected Sequence.runningReduceIndexed to link to kk_sequence_runningReduceIndexed, got \(linksRunningReduceIndexed.sorted())"
            )
        }

        do {
            // testSequenceMaxOfResolvesInCallExpressions -> Sequence.maxOf
            let memberFQNameMaxOf = ["kotlin", "sequences", "Sequence", "maxOf"].map { ctx.interner.intern($0) }
            let linksMaxOf = Set(
                sema.symbols.lookupAll(fqName: memberFQNameMaxOf).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksMaxOf.contains("kk_sequence_maxOf"),
                "Expected Sequence.maxOf to link to kk_sequence_maxOf, got \(linksMaxOf.sorted())"
            )
        }

        do {
            // testSequenceMinResolvesInCallExpressions -> Sequence.min
            let memberFQNameMin = ["kotlin", "sequences", "Sequence", "min"].map { ctx.interner.intern($0) }
            let linksMin = Set(
                sema.symbols.lookupAll(fqName: memberFQNameMin).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksMin.contains("kk_sequence_min"),
                "Expected Sequence.min to link to kk_sequence_min, got \(linksMin.sorted())"
            )
        }

        do {
            // testSequenceMaxResolvesInCallExpressions -> Sequence.max
            let memberFQNameMax = ["kotlin", "sequences", "Sequence", "max"].map { ctx.interner.intern($0) }
            let linksMax = Set(
                sema.symbols.lookupAll(fqName: memberFQNameMax).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksMax.contains("kk_sequence_max"),
                "Expected Sequence.max to link to kk_sequence_max, got \(linksMax.sorted())"
            )
        }

        do {
            // testSequenceMinOfOrNullResolvesInCallExpressions -> Sequence.minOfOrNull
            let memberFQNameMinOfOrNull = ["kotlin", "sequences", "Sequence", "minOfOrNull"].map { ctx.interner.intern($0) }
            let linksMinOfOrNull = Set(
                sema.symbols.lookupAll(fqName: memberFQNameMinOfOrNull).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksMinOfOrNull.contains("kk_sequence_minOfOrNull"),
                "Expected Sequence.minOfOrNull to link to kk_sequence_minOfOrNull, got \(linksMinOfOrNull.sorted())"
            )
        }

        do {
            // testSequenceMinByResolvesInCallExpressions -> Sequence.minBy
            let memberFQNameMinBy = ["kotlin", "sequences", "Sequence", "minBy"].map { ctx.interner.intern($0) }
            let linksMinBy = Set(
                sema.symbols.lookupAll(fqName: memberFQNameMinBy).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksMinBy.contains("kk_sequence_minBy"),
                "Expected Sequence.minBy to link to kk_sequence_minBy, got \(linksMinBy.sorted())"
            )
        }

        do {
            // testSequenceScanIndexedResolvesInCallExpressions -> Sequence.scanIndexed
            let memberFQNameScanIndexed = ["kotlin", "sequences", "Sequence", "scanIndexed"].map { ctx.interner.intern($0) }
            let linksScanIndexed = Set(
                sema.symbols.lookupAll(fqName: memberFQNameScanIndexed).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksScanIndexed.contains("kk_sequence_scanIndexed"),
                "Expected Sequence.scanIndexed to link to kk_sequence_scanIndexed, got \(linksScanIndexed.sorted())"
            )
        }

        do {
            // testSequenceReduceRightIndexedResolvesInCallExpressions -> Sequence.reduceRightIndexed
            let memberFQNameReduceRightIndexed = ["kotlin", "sequences", "Sequence", "reduceRightIndexed"].map { ctx.interner.intern($0) }
            let linksReduceRightIndexed = Set(
                sema.symbols.lookupAll(fqName: memberFQNameReduceRightIndexed).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksReduceRightIndexed.contains("kk_sequence_reduceRightIndexed"),
                "Expected Sequence.reduceRightIndexed to link to kk_sequence_reduceRightIndexed, got \(linksReduceRightIndexed.sorted())"
            )
        }

        // testSequenceReduceRightIndexedOrNullResolvesInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceReduceRightOrNullResolvesInCallExpressions -> Sequence.reduceRightOrNull
            let memberFQNameReduceRightOrNull = ["kotlin", "sequences", "Sequence", "reduceRightOrNull"].map { ctx.interner.intern($0) }
            let linksReduceRightOrNull = Set(
                sema.symbols.lookupAll(fqName: memberFQNameReduceRightOrNull).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksReduceRightOrNull.contains("kk_sequence_reduceRightOrNull"),
                "Expected Sequence.reduceRightOrNull to link to kk_sequence_reduceRightOrNull, got \(linksReduceRightOrNull.sorted())"
            )
        }

        // testSequenceScanResolvesInCallExpressions -> no additional link assertion (source only)

        // testSequenceRequireNoNullsResolvesNullableReceiverInCallExpressions -> no additional link assertion (source only)

        do {
            // testSequenceMaxByResolvesInCallExpressions -> Sequence.maxBy
            let memberFQNameMaxBy = ["kotlin", "sequences", "Sequence", "maxBy"].map { ctx.interner.intern($0) }
            let linksMaxBy = Set(
                sema.symbols.lookupAll(fqName: memberFQNameMaxBy).compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                linksMaxBy.contains("kk_sequence_maxBy"),
                "Expected Sequence.maxBy to link to kk_sequence_maxBy, got \(linksMaxBy.sorted())"
            )
        }

        // testSequenceMaxByOrNullResolvesInCallExpressions -> no additional link assertion (source only)

        // testSequenceMinByOrNullResolvesInCallExpressions -> no additional link assertion (source only)
            // === testSequenceRandomResolvesInCallExpressions ===
            do {
                let fq = ["kotlin", "sequences", "Sequence", "random"].map { interner.intern($0) }
                let links = Set(sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) })
                #expect(links.contains("kk_sequence_random"))
            }
            // === testSequenceWithIndexResolvesInCallExpressions ===
            do {
                let extensionFQName = ["kotlin", "sequences", "withIndex"]
                    .map { interner.intern($0) }
                let withIndexSymbol = try #require(
                    sema.symbols.lookup(fqName: extensionFQName),
                    "Expected Sequence.withIndex source extension to be registered"
                )
                #expect(sema.symbols.externalLinkName(for: withIndexSymbol) == nil)

                let indexedValueSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("IndexedValue"),
                ]))
                let signature = try #require(sema.symbols.functionSignature(for: withIndexSymbol))
                guard case let .classType(sequenceType) = sema.types.kind(of: signature.returnType),
                      let firstArg = sequenceType.args.first
                else {
                    Issue.record("Expected Sequence.withIndex() to return Sequence<IndexedValue<T>>")
                    return
                }
                let elementType: TypeID
                switch firstArg {
                case .invariant(let t), .out(let t), .in(let t):
                    elementType = t
                case .star:
                    Issue.record("Expected Sequence.withIndex() element type, got star projection")
                    return
                }
                guard case let .classType(indexedValueType) = sema.types.kind(of: elementType) else {
                    Issue.record("Expected Sequence.withIndex() to return Sequence<IndexedValue<T>>")
                    return
                }
                #expect(indexedValueType.classSymbol == indexedValueSymbol)
            }
            // === testSequenceSumByResolvesInCallExpressions ===
            do {
                let memberFQName = ["kotlin", "sequences", "Sequence", "sumBy"]
                    .map { interner.intern($0) }
                let sumBySymbols = sema.symbols.lookupAll(fqName: memberFQName)
                let links = Set(sumBySymbols.compactMap { sema.symbols.externalLinkName(for: $0) })
                #expect(links.contains("kk_sequence_sumBy"))
                let sumBySymbol = try #require(sumBySymbols.first)
                #expect(
                    sema.symbols.annotations(for: sumBySymbol).contains { $0.annotationFQName == "kotlin.Deprecated" },
                    "Sequence.sumBy should carry Deprecated metadata"
                )
            }
            // === testSequenceSumByDoubleResolvesInCallExpressions ===
            do {
                let memberFQName = ["kotlin", "sequences", "Sequence", "sumByDouble"]
                    .map { interner.intern($0) }
                let sumByDoubleSymbols = sema.symbols.lookupAll(fqName: memberFQName)
                let links = Set(sumByDoubleSymbols.compactMap { sema.symbols.externalLinkName(for: $0) })
                #expect(links.contains("kk_sequence_sumByDouble"))
                let sumByDoubleSymbol = try #require(sumByDoubleSymbols.first)
                #expect(
                    sema.symbols.annotations(for: sumByDoubleSymbol).contains { $0.annotationFQName == "kotlin.Deprecated" },
                    "Sequence.sumByDouble should carry Deprecated metadata"
                )
            }
            // === testSequenceMinWithOrNullResolvesInCallExpressions ===
            do {
                let memberFQName = ["kotlin", "sequences", "Sequence", "minWithOrNull"]
                    .map { interner.intern($0) }
                let symbols = sema.symbols.lookupAll(fqName: memberFQName)
                let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
                #expect(links.contains("kk_sequence_minWithOrNull"))

                let symbol = try #require(symbols.first)
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(signature.parameterTypes.count == 1)
            }
            // === testSequenceFilterIsInstanceToResolvesInCallExpressions ===
            do {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "filterIsInstanceTo"
                })
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected Sequence.filterIsInstanceTo to bind to its synthetic runtime callee"
                )
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_sequence_filterIsInstanceTo")
                #expect(
                    sema.bindings.isCollectionExpr(callExpr),
                    "Expected filterIsInstanceTo result to be tracked as a collection expression"
                )
            }
            // === testSequenceMinOrNullResolvesInCallExpressions ===
            do {
                let memberFQName = ["kotlin", "sequences", "Sequence", "minOrNull"]
                    .map { interner.intern($0) }
                let symbols = sema.symbols.lookupAll(fqName: memberFQName)
                let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
                #expect(links.contains("kk_sequence_minOrNull"))

                let symbol = try #require(symbols.first)
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(signature.typeParameterUpperBoundsList.count == 1)
                #expect(!signature.typeParameterUpperBoundsList[0].isEmpty)
            }
            // === testSequenceMinWithResolvesInCallExpressions ===
            do {
                let memberFQName = ["kotlin", "sequences", "Sequence", "minWith"]
                    .map { interner.intern($0) }
                let symbols = sema.symbols.lookupAll(fqName: memberFQName)
                let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
                #expect(links.contains("kk_sequence_minWith"))

                let symbol = try #require(symbols.first)
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(signature.parameterTypes.count == 1)
            }
        }
    }
}
