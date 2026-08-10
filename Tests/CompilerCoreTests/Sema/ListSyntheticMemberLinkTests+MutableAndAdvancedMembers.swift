#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Mutable-collection, Map, Build, Grouping, and zip/sort/conversion
/// test methods of `ListSyntheticMemberLinkTests`, split out to keep
/// each test source focused.
extension ListSyntheticMemberLinkTests {

    /// Regression: listOf(...).contains/isEmpty must not emit KSWIFTK-SEMA-VAR-OUT.
    /// The synthetic List type uses .out projection; variance relaxation must apply.

    /// Map member calls (containsKey, put, remove) go through the collection-fallback
    /// inference path which does not record a callBinding. Instead we verify that the
    /// synthetic symbols in the symbol table carry the correct external link names.

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        diagnosticsForPath(path, in: ctx).filter { $0.code == code }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func lastExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        var result: ExprID?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { result = exprID }
        }
        return result
    }

    private func allExprIDsInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func memberCallExprIDsInPath(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

    private func firstUserObjectLiteralDeclIDInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager
    ) -> DeclID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  let range = ast.arena.exprRange(exprID),
                  sourceManager.path(of: range.start.file) == path
            else { continue }
            return declID
        }
        return nil
    }

    private func findMainBodyStatementsInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> [ExprID]? {
        guard let fileID = sourceManager.fileID(forPath: path) else { return nil }
        for file in ast.files {
            guard file.fileID == fileID else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Consolidated runFrontend clean tests

    @Test
    func testRunFrontendCleanMutableAndAdvancedMembers() throws {

        let sources: [String] = [
            // testListSortedAndSortedDescendingRequireComparableElements
            """
            package sample0

                    class Box

                    fun render(values: List<Box>) {
                        values.sorted()
                        values.sortedDescending()
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runFrontend(ctx)
            try? SemaPhase().run(ctx)

            let interner = ctx.interner

            // === testListSortedAndSortedDescendingRequireComparableElements ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let boundDiagnostics = sample0Diagnostics.filter { $0.code == "KSWIFTK-SEMA-BOUND" }
                #expect(boundDiagnostics.count == 2, "Expected bound diagnostics for sorted/sortedDescending")

            }

        }
    }

    // MARK: - Consolidated runFrontend error tests

    @Test
    func testRunFrontendWithExpectedDiagnosticsMutableAndAdvancedMembers() throws {

        let sources: [String] = [
            // testStringAsIterableImplicitReceiverDoesNotExposeListOnlyMembers
            """
            package sample0

                    fun probe(): Char = with("hello") {
                        asIterable().get(0)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runFrontend(ctx)
            try? SemaPhase().run(ctx)

            let interner = ctx.interner

            // === testStringAsIterableImplicitReceiverDoesNotExposeListOnlyMembers ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0024", in: sample0Diagnostics)

            }

        }
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaCleanMutableAndAdvancedMembers() throws {

        let sources: [String] = [
            // testListSortedAndSortedDescendingHaveComparableUpperBound
            """
            package sample0
            fun noop() {}
            """,
            // testListConversionMembersUseRuntimeExternalLinks
            """
            package sample1

                    fun convert(values: List<Int>) {
                        values.toMutableList()
                        values.toSet()
                        values.joinToString(", ")
                    }

            """,
            // testCollectionAndIterableConversionMembersUseRuntimeExternalLinks
            """
            package sample2
            fun noop() {}
            """,
            // testSetBinaryMembersKeepSetResultTypeInFallbackPath
            """
            package sample3

                    fun combine(values: Set<Int>, other: Set<Int>) {
                        val left = values.intersect(other)
                        val middle = values.union(other)
                        val right = values.subtract(other)
                    }

            """,
            // testListUnzipUsesRuntimeExternalLinkAndReturnsPairOfLists
            """
            package sample4

                    fun split(values: List<Pair<Int, String>>) {
                        val result: Pair<List<Int>, List<String>> = values.unzip()
                    }

            """,
            // testSequenceJoinToStringUsesRuntimeExternalLink
            """
            package sample5

                    fun render(values: Sequence<Int>) {
                        println(values.joinToString(", "))
                        println(values.joinToString(prefix = "<", postfix = ">"))
                    }

            """,
            // testSequenceReduceIndexedOrNullUsesRuntimeExternalLink
            """
            package sample6

                    fun render(values: Sequence<Int>) {
                        println(values.reduceIndexedOrNull { index, acc, value -> acc + index * value })
                    }

            """,
            // testListFlatMapBindsToBundledSource
            """
            package sample7

                    fun render(values: List<String>) {
                        val result: List<Int> = values.flatMap { listOf(it.length) }
                        println(result)
                    }

            """,
            // testSequenceFlatMapIndexedRegistersIterableAndSequenceOverloads
            """
            package sample8

                    fun render(values: Sequence<Int>) {
                        val iterableResult = values.flatMapIndexed { index, value -> listOf(index, value * 10) }
                        val sequenceResult = values.flatMapIndexed { index, value -> sequenceOf(index + value, value * 100) }
                        println(iterableResult.toList())
                        println(sequenceResult.toList())
                    }

            """,
            // testSequenceShuffledUsesRuntimeExternalLinks
            """
            package sample9

                    import kotlin.random.Random

                    fun render(values: Sequence<Int>) {
                        values.shuffled()
                        values.shuffled(Random)
                    }

            """,
            // testSequenceRequireNoNullsIsBundledSourceWithNoRuntimeLink
            """
            package sample10

                    fun render(values: Sequence<Int?>) {
                        val result: Sequence<Int> = values.requireNoNulls()
                        println(result.toList())
                    }

            """,
            // testMutableListMutationMembersUseRuntimeExternalLinks
            """
            package sample11

                    fun mutate(values: MutableList<Int>) {
                        values.add(1)
                        values.add(1, 0)
                        values.addAll(listOf(2, 3))
                        values.removeAll(listOf(4))
                        values.retainAll(listOf(5))
                        values.removeAt(0)
                        values.removeFirst()
                        values.removeFirstOrNull()
                        values.removeLast()
                        values.removeLastOrNull()
                        values.clear()
                        values.fill(9)
                    }

            """,
            // testMutableListBulkMutationFallbacksReturnBoolean
            """
            package sample12

                    fun mutate(): Boolean {
                        val values = listOf(1, 2, 3).toMutableList()
                        return values.addAll(listOf(4))
                            || values.removeAll(listOf(5))
                            || values.retainAll(listOf(1, 2))
                    }

            """,
            // testMutableCollectionSequenceAddAllMembersUseRuntimeExternalLinks
            """
            package sample13

                    fun appendCollection(collection: MutableCollection<Int>, source: Sequence<Int>) = collection.addAll(source)
                    fun appendList(list: MutableList<Int>, source: Sequence<Int>) = list.addAll(source)
                    fun appendSet(set: MutableSet<Int>, source: Sequence<Int>) = set.addAll(source)

            """,
            // testMutableListSortMembersUseRuntimeExternalLinks
            """
            package sample14

                    fun mutate(values: MutableList<Int>) {
                        values.sort()
                        values.sortWith { a, b -> b - a }
                        values.sortBy { it }
                        values.sortByDescending { it }
                    }

            """,
            // testListPrimitiveArrayConversionsUseRuntimeExternalLinks
            """
            package sample15
            fun noop() {}
            """,
            // testMutableListBulkMutationMembersUseInvariantReceiverTypes
            """
            package sample16
            fun noop() {}
            """,
            // testMutableListBulkCollectionMembersAcceptCollectionOfSameElementType
            """
            package sample17

                    fun mutate(values: MutableList<Int>) {
                        values.addAll(listOf(1, 2))
                        values.removeAll(listOf(3, 4))
                        values.retainAll(listOf(5, 6))
                    }

            """,
            // testMutableListBulkCollectionMembersKeepInvariantReceiverType
            """
            package sample18
            fun noop() {}
            """,
            // testOutProjectedMutableListBlocksBulkMutationMembers
            """
            package sample19

                    fun mutate(values: MutableList<out Number>) {
                        values.addAll(listOf(1, 2))
                        values.removeAll(listOf(3, 4))
                        values.retainAll(listOf(5, 6))
                    }

            """,
            // testListSortMembersRemainUnavailableOnImmutableList
            """
            package sample20

                    fun mutate(values: List<Int>) {
                        values.sort()
                        values.sortBy { it }
                        values.sortByDescending { it }
                    }

            """,
            // testMutableListBulkOperationsAcceptListArguments
            """
            package sample21

                    fun mutate(values: MutableList<Int>) {
                        values.addAll(listOf(1, 2))
                        values.removeAll(listOf(1))
                        values.retainAll(listOf(2))
                    }

            """,
            // testMutableListMatchesTransitiveCollectionConstraint
            """
            package sample22

                    fun <T> consume(values: Collection<T>): T? = values.firstOrNull()

                    fun demo(values: MutableList<Int>): Int? = consume(values)

            """,
            // testListIteratorMemberResolvesWithoutTypeConstraintFailure
            """
            package sample23

                    class IntContainer(private val elements: List<Int>) {
                        operator fun iterator(): Iterator<Int> = elements.iterator()
                    }

            """,
            // testListOfContainsAndIsEmptyDoNotEmitVarOut
            """
            package sample24

                    fun main() {
                        val list = listOf(1, 2, 3)
                        list.contains(2)
                        list.contains(5)
                        list.isEmpty()
                    }

            """,
            // testListElementAtUsesBundledSourceFunction
            """
            package sample25

                    fun main() {
                        val list = listOf(1, 2, 3)
                        list.elementAt(1)
                    }

            """,
            // testListElementAtOrNullUsesBundledSourceFunction
            """
            package sample26

                    fun main() {
                        val list = listOf(1, 2, 3)
                        list.elementAtOrNull(1)
                    }

            """,
            // testSetMembersUseRuntimeExternalLinks
            """
            package sample27

                    fun check(values: Set<Int>) {
                        values.contains(42)
                    }

            """,
            // testSetRegistersCollectionAsNominalSupertype
            """
            package sample28
            fun noop() {}
            """,
            // testContainsAllMembersUseCollectionRuntimeExternalLinks
            """
            package sample29
            fun noop() {}
            """,
            // testSetContainsAllUsesCollectionParameterType
            """
            package sample30
            fun noop() {}
            """,
            // testContainsMembersAreMarkedOperatorFunctions
            """
            package sample31
            fun noop() {}
            """,
            // testWithIndexUsesIterableOfIndexedValueSignature
            """
            package sample32
            fun noop() {}
            """,
            // testMutableSetMutationMembersUseRuntimeExternalLinks
            """
            package sample33

                    fun mutate(values: MutableSet<Int>) {
                        values.add(1)
                        values.remove(1)
                        values.addAll(listOf(2, 3))
                        values.addAll(setOf(2, 3))
                        values.clear()
                    }

            """,
            // testMutableListBulkMutationMembersUseInvariantReceiverType
            """
            package sample34
            fun noop() {}
            """,
            // testMutableSetClearIsNotMarkedOperatorFunction
            """
            package sample35
            fun noop() {}
            """,
            // testMutableSetAddAllUsesCollectionParameterType
            """
            package sample36
            fun noop() {}
            """,
            // testMapSyntheticSymbolsHaveCorrectExternalLinkNames
            """
            package sample37

                    fun noop() {}

            """,
            // testMapWithDefaultSurfaceResolvesDefaultLambda
            """
            package sample38

                    fun probe(values: Map<Int, Int>): Int {
                        val defaults = values.withDefault { it * 10 }
                        return defaults.getValue(7)
                    }

            """,
            // testIndexedAndAggregateListMembersAreInlineSynthetic
            """
            package sample39
            fun noop() {}
            """,
            // testListFilterIndexedUsesBundledSource
            """
            package sample40

                    fun main() {
                        val list = listOf(10, 20, 30)
                        list.filterIndexed { index, value -> index + value > 20 }
                    }

            """,
            // testListFilterIsInstanceUsesBundledSource
            """
            package sample41

                    fun main() {
                        val list: List<Any> = listOf(1, "two", 3)
                        list.filterIsInstance<Int>()
                    }

            """,
            // testListFilterHOFsUseBundledSourceCalls
            """
            package sample42

                    fun main() {
                        val values = listOf(10, 20, 30)
                        val nullable: List<Int?> = listOf(1, null, 3)
                        val mixed: List<Any> = listOf(1, "two", 3)
                        values.filter { value -> value > 10 }
                        values.filterNot { value -> value == 20 }
                        nullable.filterNotNull()
                        values.filterIndexed { index, value -> index + value > 20 }
                        mixed.filterIsInstance<Int>()
                    }

            """,
            // testMapHigherOrderMembersAreInlineAndToListPreservesPairType
            """
            package sample43
            fun noop() {}
            """,
            // testMapEntryToPairSurfaceIsRegistered
            """
            package sample44

                    fun probe(values: Map<String, Int>): List<Pair<String, Int>> {
                        return values.map { it.toPair() }
                    }

            """,
            // testBuildListInfersElementTypeFromBuilderCalls
            """
            package sample45

                    fun render(): List<Int> = buildList {
                        this.add(1)
                        add(2)
                    }

            """,
            // testBuildMapInfersKeyAndValueTypesFromBuilderCalls
            """
            package sample46

                    fun render(): Map<String, Int> = buildMap {
                        this.put("a", 1)
                        put("b", 2)
                    }

            """,
            // testMapKeysToResolvesWithMutableMapDestination
            """
            package sample47

                    fun remap(values: Map<Int, String>, destination: MutableMap<Int, String>): MutableMap<Int, String> {
                        return values.mapKeysTo(destination) { entry -> entry.key + 10 }
                    }

            """,
            // testMapValuesToResolvesWithMutableMapDestination
            """
            package sample48

                    fun remap(values: Map<Int, String>, destination: MutableMap<Int, Int>): MutableMap<Int, Int> {
                        return values.mapValuesTo(destination) { entry -> entry.value.length }
                    }

            """,
            // testMutableMapPutAllUsesProjectedMapParameterType
            """
            package sample49
            fun noop() {}
            """,
            // testGroupingEachCountToUsesProjectedMutableMapParameterType
            """
            package sample50
            fun noop() {}
            """,
            // testBuildListCapacityOverloadResolves
            """
            package sample51

                    fun render(): List<Int> = buildList(4) {
                        add(1)
                        add(2)
                    }

            """,
            // testListZipWithNextOverloadsInferReturnTypes
            """
            package sample52

                    fun pairs(values: List<Int>) = values.zipWithNext()
                    fun gaps(values: List<Int>) = values.zipWithNext { left, right -> right - left }

            """,
            // testListZipUsesRuntimeExternalLinkAndReturnsPairList
            """
            package sample53

                    fun zipValues(values: List<Int>, labels: List<String>) = values.zip(labels)

            """,
            // testListFlatMapIndexedBindsToBundledSource
            """
            package sample54

                    fun render(values: List<String>) {
                        val result: List<Int> = values.flatMapIndexed { index, value -> listOf(index + value.length) }
                        println(result)
                    }

            """,
            // testListToBooleanArrayUsesRuntimeExternalLink
            """
            package sample55

                    fun convert(values: List<Boolean>) {
                        values.toBooleanArray()
                    }

            """,
            // testListToShortArrayUsesRuntimeExternalLink
            """
            package sample56

                    fun convert(values: List<Short>) {
                        values.toShortArray()
                    }

            """,
            // testListToDoubleArrayUsesRuntimeExternalLink
            """
            package sample57

                    fun convert(values: List<Double>) {
                        values.toDoubleArray()
                    }

            """,
            // testListToFloatArrayUsesRuntimeExternalLink
            """
            package sample58

                    fun convert(values: List<Float>) {
                        values.toFloatArray()
                    }

            """,
            // testCollectionAndIterableConversionMembersUseRuntimeExternalLinks (toMutableList/Collection)
            """
            package sample59

                    fun copy(values: Collection<String>) {
                        values.toMutableList()
                    }
            """,
            // testCollectionAndIterableConversionMembersUseRuntimeExternalLinks (toTypedArray)
            """
            package sample60

                    fun copy(values: Collection<String>) {
                        values.toTypedArray()
                    }
            """,
            // testCollectionAndIterableConversionMembersUseRuntimeExternalLinks (toMutableList/Iterable)
            """
            package sample61

                    fun copy(values: Iterable<String>) {
                        values.toMutableList()
                    }
            """,
            // testCollectionAndIterableConversionMembersUseRuntimeExternalLinks (toMutableSet)
            """
            package sample62

                    fun copy(values: Iterable<String>) {
                        values.toMutableSet()
                    }
            """,
            // testListPrimitiveArrayConversionsUseRuntimeExternalLinks (toBooleanArray)
            """
            package sample63

                    fun convert(values: List<Boolean>) {
                        values.toBooleanArray()
                    }
            """,
            // testListPrimitiveArrayConversionsUseRuntimeExternalLinks (toByteArray)
            """
            package sample64

                    fun convert(values: List<Byte>) {
                        values.toByteArray()
                    }
            """,
            // testListPrimitiveArrayConversionsUseRuntimeExternalLinks (toShortArray)
            """
            package sample65

                    fun convert(values: List<Short>) {
                        values.toShortArray()
                    }
            """,
            // testListPrimitiveArrayConversionsUseRuntimeExternalLinks (toIntArray)
            """
            package sample66

                    fun convert(values: List<Int>) {
                        values.toIntArray()
                    }
            """,
            // testListPrimitiveArrayConversionsUseRuntimeExternalLinks (toDoubleArray)
            """
            package sample67

                    fun convert(values: List<Double>) {
                        values.toDoubleArray()
                    }
            """,
            // testListPrimitiveArrayConversionsUseRuntimeExternalLinks (toFloatArray)
            """
            package sample68

                    fun convert(values: List<Float>) {
                        values.toFloatArray()
                    }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testListSortedAndSortedDescendingHaveComparableUpperBound ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let baseFQName: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("List"),
                ]
                let memberCases: [(String, String)] = [
                    ("sorted", "kk_list_sorted"),
                    ("sortedDescending", "kk_list_sortedDescending"),
                ]

                for (memberName, externalLinkName) in memberCases {
                    let symbolID = try #require(sema.symbols.lookupAll(
                            fqName: baseFQName + [interner.intern(memberName)]
                        ).first(where: { sema.symbols.externalLinkName(for: $0) == externalLinkName }))
                    let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                    #expect(signature.typeParameterUpperBoundsList.count == 1)
                    let upperBounds = signature.typeParameterUpperBoundsList[0]
                    #expect(upperBounds.count == 1, "Expected Comparable upper bound for \(memberName) element type")

                    guard case let .classType(boundType) = sema.types.kind(of: upperBounds[0]) else {
                        Issue.record("Expected \(memberName) upper bound to be a class type"); return
                    }

                    #expect(boundType.classSymbol == sema.types.comparableInterfaceSymbol)
                    #expect(boundType.args.count == 1)

                    guard case let .invariant(argumentType) = boundType.args[0] else {
                        Issue.record("Expected \(memberName) upper bound to reference invariant element type"); return
                    }

                    let expectedElementType = sema.types.make(.typeParam(TypeParamType(
                        symbol: signature.typeParameterSymbols[0],
                        nullability: .nonNull
                    )))
                    #expect(argumentType == expectedElementType)
                }

            }

            // === testListConversionMembersUseRuntimeExternalLinks ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let source = sources[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let expectedExternalLinks: [String: String?] = [
                    "toMutableList": "kk_list_to_mutable_list",
                    "toSet": "kk_list_to_set",
                    // KSP-INF-011: List<T>.joinToString is now source-backed
                    // (StringSplitJoin.kt) and its body delegates to the private
                    // __kk_string_joinToString bridge with external link
                    // kk_list_joinToString. The public member itself has no
                    // external link name.
                    "joinToString": nil,
                ]

                for (memberName, externalLinkName) in expectedExternalLinks {
                    if memberName == "addAll" {
                        let symbol = try #require(sema.symbols.lookup(fqName: [
                            interner.intern("kotlin"),
                            interner.intern("collections"),
                            interner.intern("MutableSet"),
                            interner.intern(memberName),
                        ]))
                        #expect(sema.symbols.externalLinkName(for: symbol) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
                    } else {
                        // Exclude bundled stdlib files (FileIDs 0 and 1) to avoid matching
                        // internal calls like `result.add(element)` inside bundled Set HOFs.
                        let callExpr = try #require(firstExprIDInPath(in: ast, path: sample1Path, ctx: ctx) { id, expr in
                            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                            guard interner.resolve(callee) == memberName else { return false }
                            if let range = ast.arena.exprRange(id), range.start.file.rawValue < 2 {
                                return false
                            }
                            return true
                        })
                        let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                        #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
                    }
                }

            }

            // === testCollectionAndIterableConversionMembersUseRuntimeExternalLinks ===

            do {
                let cases: [SyntheticMemberCallCase] = [
                    .init(source: "", memberName: "toMutableList", expectedExternalLink: "kk_collection_toMutableList", expectedTypeShape: .classNamed("MutableList")),
                    .init(source: "", memberName: "toTypedArray", expectedExternalLink: "kk_collection_toTypedArray", expectedTypeShape: .classNamed("Array")),
                    .init(source: "", memberName: "toMutableList", expectedExternalLink: "kk_iterable_toMutableList", expectedTypeShape: .classNamed("MutableList")),
                    .init(source: "", memberName: "toMutableSet", expectedExternalLink: "kk_iterable_toMutableSet", expectedTypeShape: .classNamed("MutableSet")),
                ]

                let base = 59
                for (offset, testCase) in cases.enumerated() {
                    let samplePath = paths[base + offset]
                    try assertSyntheticMemberCall(testCase, in: ctx, ast: ast, sema: sema, path: samplePath)
                }
            }

            // === testSetBinaryMembersKeepSetResultTypeInFallbackPath ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let expectedMembers = Set(["intersect", "union", "subtract"])
                let setResultTypes: [String: TypeID] = Dictionary(uniqueKeysWithValues: ast.arena.exprs.indices.compactMap { index in
                    let exprID = ExprID(rawValue: Int32(index))
                    guard let expr = ast.arena.expr(exprID),
                          case let .memberCall(_, callee, _, _, _) = expr
                    else {
                        return nil
                    }
                    let memberName = interner.resolve(callee)
                    guard expectedMembers.contains(memberName),
                          let type = sema.bindings.exprType(for: exprID)
                    else {
                        return nil
                    }
                    return (memberName, type)
                })

                #expect(setResultTypes.keys.count == expectedMembers.count)

                for memberName in expectedMembers {
                    let type = try #require(setResultTypes[memberName])
                    guard case let .classType(classType) = sema.types.kind(of: type) else {
                        Issue.record("Expected \(memberName) to infer as Set<Int>, got \(sema.types.kind(of: type))"); return
                    }
                    #expect(try interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "Set")
                    #expect(classType.args.count == 1, "Expected Set<Int> type argument for \(memberName)")
                    let elementType: TypeID
                    switch classType.args[0] {
                    case let .invariant(type), let .out(type), let .in(type):
                        elementType = type
                    case .star:
                        Issue.record("Expected concrete Set element projection for \(memberName)"); return
                    }
                    #expect(sema.types.kind(of: elementType) == .primitive(.int, .nonNull))
                }

            }

            // === testListUnzipUsesRuntimeExternalLinkAndReturnsPairOfLists ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                #expect(sample4Diagnostics.isEmpty, "Expected List.unzip to type-check cleanly, got: \(sample4Diagnostics)")

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample4Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "unzip"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_unzip")

                let resultType = try #require(sema.bindings.exprType(for: callExpr))
                guard case let .classType(pairType) = sema.types.kind(of: resultType) else {
                    Issue.record("Expected List.unzip to return Pair<List<Int>, List<String>>"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(pairType.classSymbol)?.name)) == "Pair")
                #expect(pairType.args.count == 2)

                let firstListType = try projectedType(pairType.args[0])
                let secondListType = try projectedType(pairType.args[1])
                try assertListType(firstListType, elementType: sema.types.intType, sema: sema, interner: interner)
                try assertListType(secondListType, elementType: sema.types.stringType, sema: sema, interner: interner)

            }

            // === testSequenceJoinToStringUsesRuntimeExternalLink ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample5Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sample5Diagnostics)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample5Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, range) = expr else { return false }
                    guard interner.resolve(callee) == "joinToString" else { return false }
                    // KSP-483: bundled Stdlib/kotlin/io/Files.kt also calls
                    // List<String>.joinToString(...) internally; exclude bundled
                    // call sites so this finds the user's Sequence.joinToString(...).
                    return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_sequence_joinToString")

            }

            // === testSequenceReduceIndexedOrNullUsesRuntimeExternalLink ===

            do {

                let sample6Path = paths[6]

                let path = sample6Path

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample6Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sample6Diagnostics)

                let sequenceReduceIndexedOrNullSymbol = try #require(sema.symbols.lookup(
                        fqName: [
                            interner.intern("kotlin"),
                            interner.intern("sequences"),
                            interner.intern("Sequence"),
                            interner.intern("reduceIndexedOrNull"),
                        ]
                    ))
                #expect(sema.symbols.externalLinkName(for: sequenceReduceIndexedOrNullSymbol) == "kk_sequence_reduceIndexedOrNull")

            }

            // === testListFlatMapBindsToBundledSource ===

            do {

                let sample7Path = paths[7]

                let path = sample7Path

                let source = sources[7]

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample7Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sample7Diagnostics)

                let sourceFQName = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("flatMap"),
                ]
                let symbols = sema.symbols.lookupAll(fqName: sourceFQName)
                let listFlatMapSymbol = try #require(symbols.first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          let (receiverClassType, _) = resolveClassTypeSymbol(receiverType, sema: sema),
                          let receiverSymbol = sema.symbols.symbol(receiverClassType.classSymbol)
                    else { return false }
                    return interner.resolve(receiverSymbol.name) == "List"
                }, "Expected bundled source List.flatMap overload")

                let symbolInfo = try #require(sema.symbols.symbol(listFlatMapSymbol))
                #expect(!symbolInfo.flags.contains(.synthetic), "flatMap must be a bundled source declaration")
                #expect(sema.symbols.externalLinkName(for: listFlatMapSymbol) == nil, "source flatMap must not link to runtime")

                let symbol = listFlatMapSymbol
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType),
                      let returnSymbol = sema.symbols.symbol(returnClassType.classSymbol)
                else {
                    Issue.record("Expected List.flatMap to return List<R>"); return
                }
                #expect(interner.resolve(returnSymbol.name) == "List")

                let transformType = try #require(signature.parameterTypes.first)
                guard case let .functionType(functionType) = sema.types.kind(of: transformType),
                      let (_, transformReturnSymbol) = resolveClassTypeSymbol(functionType.returnType, sema: sema)
                else {
                    Issue.record("Expected List.flatMap transform to return List<R>"); return
                }
                #expect(interner.resolve(transformReturnSymbol.name) == "List")

            }

            // === testSequenceFlatMapIndexedRegistersIterableAndSequenceOverloads ===

            do {

                let sample8Path = paths[8]

                let path = sample8Path

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample8Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sample8Diagnostics)

                let packageFQName = [
                    interner.intern("kotlin"),
                    interner.intern("sequences"),
                    interner.intern("flatMapIndexed"),
                ]
                let sequenceFQName = [
                    interner.intern("kotlin"),
                    interner.intern("sequences"),
                    interner.intern("Sequence"),
                ]
                guard let sequenceSymbol = sema.symbols.lookup(fqName: sequenceFQName) else {
                    #expect(false, "Sequence symbol not found")
                    return
                }
                let allSymbols = sema.symbols.lookupAll(fqName: packageFQName)
                let symbols = allSymbols.filter { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          let (receiverClassType, _) = resolveClassTypeSymbol(signature.receiverType ?? sema.types.anyType, sema: sema)
                    else { return false }
                    return receiverClassType.classSymbol == sequenceSymbol
                }
                #expect(symbols.count == 2, "Expected Iterable and Sequence flatMapIndexed overloads")
                #expect(symbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil }, "Source-backed flatMapIndexed must not link to runtime")

                let transformReturnTypeNames = symbols.compactMap { symbolID -> String? in
                    guard let parameterType = sema.symbols.functionSignature(for: symbolID)?.parameterTypes.first,
                          case let .functionType(functionType) = sema.types.kind(of: parameterType),
                          let (_, returnSymbol) = resolveClassTypeSymbol(functionType.returnType, sema: sema)
                    else { return nil }
                    return interner.resolve(returnSymbol.name)
                }
                #expect(transformReturnTypeNames.contains("Iterable"))
                #expect(transformReturnTypeNames.contains("Sequence"))

            }

            // === testSequenceShuffledUsesRuntimeExternalLinks ===

            do {

                let sample9Path = paths[9]

                let path = sample9Path

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample9Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sample9Diagnostics)

                let fqName = [
                    interner.intern("kotlin"),
                    interner.intern("sequences"),
                    interner.intern("Sequence"),
                    interner.intern("shuffled"),
                ]
                let externalLinks = Set(sema.symbols.lookupAll(fqName: fqName).compactMap {
                    sema.symbols.externalLinkName(for: $0)
                })
                #expect(externalLinks.contains("kk_sequence_shuffled"))
                #expect(externalLinks.contains("kk_sequence_shuffled_random"))

            }

            // === testSequenceRequireNoNullsIsBundledSourceWithNoRuntimeLink ===

            do {

                let sample10Path = paths[10]

                let path = sample10Path

                let source = sources[10]

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample10Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sample10Diagnostics)

                let packageFQName = [
                    interner.intern("kotlin"),
                    interner.intern("sequences"),
                    interner.intern("requireNoNulls"),
                ]
                let sequenceFQName = [
                    interner.intern("kotlin"),
                    interner.intern("sequences"),
                    interner.intern("Sequence"),
                ]
                guard let sequenceSymbol = sema.symbols.lookup(fqName: sequenceFQName) else {
                    #expect(false, "Sequence symbol not found")
                    return
                }
                let candidates = sema.symbols.lookupAll(fqName: packageFQName).filter { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          let (receiverClassType, _) = resolveClassTypeSymbol(signature.receiverType ?? sema.types.anyType, sema: sema)
                    else { return false }
                    return receiverClassType.classSymbol == sequenceSymbol
                }
                #expect(candidates.isEmpty == false, "Expected a bundled source requireNoNulls")
                #expect(candidates.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil }, "Source-backed requireNoNulls must not have a runtime link")

            }

            // === testMutableListMutationMembersUseRuntimeExternalLinks ===

            do {

                let sample11Path = paths[11]

                let path = sample11Path

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                let expectedExternalLinks: [(String, Int, String)] = [
                    ("add", 1, "kk_mutable_list_add"),
                    ("add", 2, "kk_mutable_list_add_at"),
                    ("addAll", 1, "kk_mutable_list_addAll"),
                    ("removeAll", 1, "kk_mutable_list_removeAll"),
                    ("retainAll", 1, "kk_mutable_list_retainAll"),
                    ("removeAt", 1, "kk_mutable_list_removeAt"),
                    ("removeFirst", 0, "kk_mutable_list_removeFirst"),
                    ("removeFirstOrNull", 0, "kk_mutable_list_removeFirstOrNull"),
                    ("removeLast", 0, "kk_mutable_list_removeLast"),
                    ("removeLastOrNull", 0, "kk_mutable_list_removeLastOrNull"),
                    ("clear", 0, "kk_mutable_list_clear"),
                    ("fill", 1, "kk_mutable_list_fill"),
                ]

                for (memberName, argumentCount, externalLinkName) in expectedExternalLinks {
                    let callExpr = try #require(lastExprIDInPath(in: ast, path: sample11Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, valueArgs, _) = expr else { return false }
                        return interner.resolve(callee) == memberName && valueArgs.count == argumentCount
                    })
                    let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName)/\(argumentCount) to resolve to \(externalLinkName)")
                }

            }

            // === testMutableListBulkMutationFallbacksReturnBoolean ===

            do {

                let sample12Path = paths[12]

                let path = sample12Path

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                for memberName in ["addAll", "removeAll", "retainAll"] {
                    let callExpr = try #require(firstExprIDInPath(in: ast, path: sample12Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == memberName
                    })
                    let symbolID = try #require(sema.symbols.lookup(
                            fqName: [
                                interner.intern("kotlin"),
                                interner.intern("collections"),
                                interner.intern("MutableList"),
                                interner.intern(memberName),
                            ]
                        ))

                    #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_mutable_list_\(memberName)", "Expected \(memberName) to resolve to runtime extern")
                    #expect(sema.bindings.exprTypes[callExpr] == sema.types.booleanType, "Expected \(memberName) to return Boolean")
                    #expect(!(sema.bindings.isCollectionExpr(callExpr)), "Expected \(memberName) result to remain a scalar Boolean")
                }

            }

            // === testMutableCollectionSequenceAddAllMembersUseRuntimeExternalLinks ===

            do {

                let sample13Path = paths[13]

                let path = sample13Path

                let sample13Diagnostics = diagnosticsForPath(sample13Path, in: ctx)

                let expectedExternalLinks = [
                    "collection": "kk_mutable_collection_addAll_sequence",
                    "list": "kk_mutable_list_addAll_sequence",
                    "set": "kk_mutable_set_addAll_sequence",
                ]

                for (receiverName, externalLinkName) in expectedExternalLinks {
                    let callExpr = try #require(firstExprIDInPath(in: ast, path: sample13Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(receiver, callee, _, valueArgs, _) = expr,
                              interner.resolve(callee) == "addAll",
                              valueArgs.count == 1,
                              case let .nameRef(name, _) = ast.arena.expr(receiver)
                        else {
                            return false
                        }
                        return interner.resolve(name) == receiverName
                    })
                    let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(receiverName).addAll(Sequence) to resolve to \(externalLinkName)")
                    #expect(sema.bindings.exprType(for: callExpr) == sema.types.booleanType)
                }

            }

            // === testMutableListSortMembersUseRuntimeExternalLinks ===

            do {

                let sample14Path = paths[14]

                let path = sample14Path

                let sample14Diagnostics = diagnosticsForPath(sample14Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample14Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0022", in: sample14Diagnostics)
                let expectedExternalLinks = [
                    "sort": "kk_mutable_list_sort",
                    "sortWith": "kk_mutable_list_sortWith",
                    "sortBy": "kk_mutable_list_sortBy",
                    "sortByDescending": "kk_mutable_list_sortByDescending",
                ]

                for (memberName, externalLinkName) in expectedExternalLinks {
                    let callExpr = try #require(firstExprIDInPath(in: ast, path: sample14Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == memberName
                    })
                    if let chosenCallee = sema.bindings.callBinding(for: callExpr)?.chosenCallee {
                        #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
                    }
                }

            }

            // === testListPrimitiveArrayConversionsUseRuntimeExternalLinks ===

            do {
                let cases: [SyntheticMemberCallCase] = [
                    .init(source: "", memberName: "toBooleanArray", expectedExternalLink: "kk_list_toBooleanArray", expectedTypeShape: .classNamed("BooleanArray")),
                    .init(source: "", memberName: "toByteArray", expectedExternalLink: "kk_list_toByteArray", expectedTypeShape: .classNamed("ByteArray")),
                    .init(source: "", memberName: "toShortArray", expectedExternalLink: "kk_list_toShortArray", expectedTypeShape: .classNamed("ShortArray")),
                    .init(source: "", memberName: "toIntArray", expectedExternalLink: "kk_list_toIntArray", expectedTypeShape: .classNamed("IntArray")),
                    .init(source: "", memberName: "toDoubleArray", expectedExternalLink: "kk_list_toDoubleArray", expectedTypeShape: .classNamed("DoubleArray")),
                    .init(source: "", memberName: "toFloatArray", expectedExternalLink: "kk_list_toFloatArray", expectedTypeShape: .classNamed("FloatArray")),
                ]

                let base = 63
                for (offset, testCase) in cases.enumerated() {
                    let samplePath = paths[base + offset]
                    try assertSyntheticMemberCall(testCase, in: ctx, ast: ast, sema: sema, path: samplePath)
                }
            }

            // === testMutableListBulkMutationMembersUseInvariantReceiverTypes ===

            do {

                let sample16Path = paths[16]

                let path = sample16Path

                let sample16Diagnostics = diagnosticsForPath(sample16Path, in: ctx)

                let ownerFQName = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("MutableList"),
                ]

                for memberName in ["addAll", "removeAll", "retainAll"] {
                    let symbolID = try #require(sema.symbols.lookup(fqName: ownerFQName + [interner.intern(memberName)]))
                    let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                    guard case let .classType(receiverType) = sema.types.kind(of: try #require(signature.receiverType)) else {
                        Issue.record("Expected \(memberName) to use MutableList receiver type"); return
                    }
                    guard case .invariant = try #require(receiverType.args.first) else {
                        Issue.record("Expected \(memberName) receiver projection to remain invariant"); return
                    }
                }

            }

            // === testMutableListBulkCollectionMembersAcceptCollectionOfSameElementType ===

            do {

                let sample17Path = paths[17]

                let path = sample17Path

                let sample17Diagnostics = diagnosticsForPath(sample17Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample17Diagnostics)

                let expectedExternalLinks = [
                    "addAll": "kk_mutable_list_addAll",
                    "removeAll": "kk_mutable_list_removeAll",
                    "retainAll": "kk_mutable_list_retainAll",
                ]

                for (memberName, externalLinkName) in expectedExternalLinks {
                    let callExpr = try #require(firstExprIDInPath(in: ast, path: sample17Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == memberName
                    })
                    let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
                }

            }

            // === testMutableListBulkCollectionMembersKeepInvariantReceiverType ===

            do {

                let sample18Path = paths[18]

                let path = sample18Path

                let sample18Diagnostics = diagnosticsForPath(sample18Path, in: ctx)

                let mutableListFQName: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("MutableList"),
                ]

                for memberName in ["addAll", "removeAll", "retainAll"] {
                    let symbolID = try #require(sema.symbols.lookup(fqName: mutableListFQName + [interner.intern(memberName)]))
                    let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                    let receiverType = try #require(signature.receiverType)
                    guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
                        Issue.record("Expected \(memberName) receiver to be a class type"); return
                    }
                    guard case .invariant = try #require(receiverClassType.args.first) else {
                        Issue.record("Expected \(memberName) receiver to keep invariant element type, got \(sema.types.renderType(receiverType))"); return
                    }

                    let parameterType = try #require(signature.parameterTypes.first)
                    guard case let .classType(parameterClassType) = sema.types.kind(of: parameterType) else {
                        Issue.record("Expected \(memberName) parameter to be a class type"); return
                    }
                    guard case .out = try #require(parameterClassType.args.first) else {
                        Issue.record("Expected \(memberName) parameter to remain covariant Collection<out E>, got \(sema.types.renderType(parameterType))"); return
                    }
                }

            }

            // === testOutProjectedMutableListBlocksBulkMutationMembers ===

            do {

                let sample19Path = paths[19]

                let path = sample19Path

                let sample19Diagnostics = diagnosticsForPath(sample19Path, in: ctx)

                let diagnostics = sample19Diagnostics.filter { $0.code == "KSWIFTK-SEMA-VAR-OUT" }
                #expect(diagnostics.count == 3, "Projected MutableList bulk writes should be rejected")
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample19Diagnostics)

            }

            // === testListSortMembersRemainUnavailableOnImmutableList ===

            do {

                let sample20Path = paths[20]

                let path = sample20Path

                let sample20Diagnostics = diagnosticsForPath(sample20Path, in: ctx)

                for memberName in ["sort", "sortBy", "sortByDescending"] {
                    let callExpr = try #require(firstExprIDInPath(in: ast, path: sample20Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == memberName
                    })
                    #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == nil, "Expected immutable List.\(memberName) to remain unresolved")
                }

                #expect(!(sample20Diagnostics.isEmpty), "Expected diagnostics for immutable List.sort* calls")

            }

            // === testMutableListBulkOperationsAcceptListArguments ===

            do {

                let sample21Path = paths[21]

                let path = sample21Path

                let sample21Diagnostics = diagnosticsForPath(sample21Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample21Diagnostics)

            }

            // === testMutableListMatchesTransitiveCollectionConstraint ===

            do {

                let sample22Path = paths[22]

                let path = sample22Path

                let sample22Diagnostics = diagnosticsForPath(sample22Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample22Diagnostics)

                let consumeCall = try #require(firstExprIDInPath(in: ast, path: sample22Path, ctx: ctx) { _, expr in
                    guard case let .call(callee, _, _, _) = expr,
                          case let .nameRef(name, _) = ast.arena.expr(callee)
                    else { return false }
                    return interner.resolve(name) == "consume"
                })

                #expect(sema.bindings.callBinding(for: consumeCall)?.chosenCallee != nil, "Expected MutableList<Int> to satisfy Collection<T> through transitive lifting")

            }

            // === testListIteratorMemberResolvesWithoutTypeConstraintFailure ===

            do {

                let sample23Path = paths[23]

                let path = sample23Path

                let sample23Diagnostics = diagnosticsForPath(sample23Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample23Diagnostics)

                let iteratorCall = try #require(firstExprIDInPath(in: ast, path: sample23Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "iterator"
                })

                let chosenCallee = try #require(sema.bindings.callBinding(for: iteratorCall)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_range_iterator")

            }

            // === testListOfContainsAndIsEmptyDoNotEmitVarOut ===

            do {

                let sample24Path = paths[24]

                let path = sample24Path

                let source = sources[24]

                let sample24Diagnostics = diagnosticsForPath(sample24Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: sample24Diagnostics)
                var containsCalls: [ExprID] = []
                for index in ast.arena.exprs.indices {
                    let exprID = ExprID(rawValue: Int32(index))
                    guard let expr = ast.arena.expr(exprID),
                          case let .memberCall(_, callee, _, _, range) = expr,
                          interner.resolve(callee) == "contains",
                          ctx.sourceManager.path(of: range.start.file) == sample24Path
                    else { continue }
                    containsCalls.append(exprID)
                }
                #expect(containsCalls.count == 2)
                for callID in containsCalls {
                    let binding = sema.bindings.callBinding(for: callID)
                    #expect(binding?.chosenCallee != nil, "contains should resolve")
                    if let chosen = binding?.chosenCallee {
                        #expect(sema.symbols.externalLinkName(for: chosen) == nil, "List.contains is source-backed and should have no external link")
                    }
                }

            }

            // === testListElementAtUsesBundledSourceFunction ===

            do {

                let sample25Path = paths[25]

                let path = sample25Path

                let sample25Diagnostics = diagnosticsForPath(sample25Path, in: ctx)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample25Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "elementAt"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosenCallee))
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                #expect(!symbol.flags.contains(.synthetic))
                #expect(interner.resolve(symbol.name) == "elementAt")

            }

            // === testListElementAtOrNullUsesBundledSourceFunction ===

            do {

                let sample26Path = paths[26]

                let path = sample26Path

                let sample26Diagnostics = diagnosticsForPath(sample26Path, in: ctx)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample26Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "elementAtOrNull"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosenCallee))
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                #expect(!symbol.flags.contains(.synthetic))
                #expect(interner.resolve(symbol.name) == "elementAtOrNull")

            }

            // === testSetMembersUseRuntimeExternalLinks ===

            do {

                let sample27Path = paths[27]

                let path = sample27Path

                let sample27Diagnostics = diagnosticsForPath(sample27Path, in: ctx)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample27Path, ctx: ctx) { id, expr in
                    guard case let .memberCall(_, callee, _, _, range) = expr else { return false }
                    guard interner.resolve(callee) == "contains" else { return false }
                    guard !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_") else { return false }
                    return true
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_set_contains", "Expected contains to resolve to kk_set_contains")

            }

            // === testSetRegistersCollectionAsNominalSupertype ===

            do {

                let sample28Path = paths[28]

                let path = sample28Path

                let sample28Diagnostics = diagnosticsForPath(sample28Path, in: ctx)

                let setSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Set"),
                ]))
                let collectionSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Collection"),
                ]))

                #expect(sema.types.directNominalSupertypes(for: setSymbol) == [collectionSymbol], "Expected Set to register Collection as its nominal supertype")

            }

            // === testContainsAllMembersUseCollectionRuntimeExternalLinks ===

            do {

                let sample29Path = paths[29]

                let path = sample29Path

                let source = sources[29]

                let sample29Diagnostics = diagnosticsForPath(sample29Path, in: ctx)

                let collectionsPkg = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                ]
                let listSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("List")]))
                let setSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("Set")]))

                func containsAllSymbol(owner: SymbolID) -> SymbolID? {
                    let name = interner.intern("containsAll")
                    func matches(_ symbolID: SymbolID) -> Bool {
                        guard let signature = sema.symbols.functionSignature(for: symbolID),
                              let receiverType = signature.receiverType,
                              case let .classType(classType) = sema.types.kind(of: receiverType)
                        else {
                            return false
                        }
                        return classType.classSymbol == owner
                    }
                    if let sourceBacked = sema.symbols.lookupAll(fqName: collectionsPkg + [name]).first(where: matches) {
                        return sourceBacked
                    }
                    guard let ownerSymbol = sema.symbols.symbol(owner) else { return nil }
                    return sema.symbols.lookupAll(fqName: ownerSymbol.fqName + [name]).first(where: matches)
                }

                let listContainsAll = try #require(containsAllSymbol(owner: listSymbol), "Expected List.containsAll source extension")
                let setContainsAll = try #require(containsAllSymbol(owner: setSymbol), "Expected Set.containsAll")

                // List.containsAll is source-backed (KSP-423); Set.containsAll still uses the runtime bridge.
                #expect(sema.symbols.externalLinkName(for: listContainsAll) == nil)
                #expect(sema.symbols.externalLinkName(for: setContainsAll) == "kk_set_containsAll")

            }

            // === testSetContainsAllUsesCollectionParameterType ===

            do {

                let sample30Path = paths[30]

                let path = sample30Path

                let sample30Diagnostics = diagnosticsForPath(sample30Path, in: ctx)

                let setContainsAll = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Set"),
                    interner.intern("containsAll"),
                ]))
                let signature = try #require(sema.symbols.functionSignature(for: setContainsAll))
                let parameterType = try #require(signature.parameterTypes.first)

                guard case let .classType(collectionType) = sema.types.kind(of: parameterType) else {
                    Issue.record("Set.containsAll should accept Collection<E>"); return
                }

                #expect(try interner.resolve(#require(sema.symbols.symbol(collectionType.classSymbol)?.name)) == "Collection")
                guard case let .out(elementType) = try #require(collectionType.args.first) else {
                    Issue.record("Collection parameter should preserve the element projection"); return
                }
                let typeParamSymbol = try #require(signature.typeParameterSymbols.first)
                let expectedElementType = sema.types.make(.typeParam(TypeParamType(
                    symbol: typeParamSymbol,
                    nullability: .nonNull
                )))
                #expect(elementType == expectedElementType)

            }

            // === testContainsMembersAreMarkedOperatorFunctions ===

            do {

                let sample31Path = paths[31]

                let path = sample31Path

                let sample31Diagnostics = diagnosticsForPath(sample31Path, in: ctx)

                let collectionsPkg = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                ]
                let listSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("List")]))
                let setSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("Set")]))

                func containsSymbol(owner: SymbolID, packageFQName: [InternedString]) -> SymbolID? {
                    let name = interner.intern("contains")
                    func matches(_ symbolID: SymbolID) -> Bool {
                        guard let signature = sema.symbols.functionSignature(for: symbolID),
                              let receiverType = signature.receiverType,
                              case let .classType(classType) = sema.types.kind(of: receiverType)
                        else {
                            return false
                        }
                        return classType.classSymbol == owner
                    }
                    if let sourceBacked = sema.symbols.lookupAll(fqName: packageFQName + [name]).first(where: matches) {
                        return sourceBacked
                    }
                    guard let ownerSymbol = sema.symbols.symbol(owner) else { return nil }
                    return sema.symbols.lookupAll(fqName: ownerSymbol.fqName + [name]).first(where: matches)
                }

                let listContains = try #require(containsSymbol(owner: listSymbol, packageFQName: collectionsPkg))
                let setContains = try #require(containsSymbol(owner: setSymbol, packageFQName: collectionsPkg))
                #expect(sema.symbols.symbol(listContains)?.flags.contains(.operatorFunction) == true)
                #expect(sema.symbols.symbol(setContains)?.flags.contains(.operatorFunction) == true)

                // KSP-408: `kotlin.text.contains` now has multiple overloads under the same
                // fqName: CharSequence.contains(other: CharSequence) (1-arg `operator fun`
                // used for `in` resolution), CharSequence.contains(other, ignoreCase) (2-arg,
                // not an operator function), and the pre-existing String.contains(regex:
                // Regex) synthetic stub (1-arg, but a different receiver type and not marked
                // as an operator function). Disambiguate by receiver type rather than relying
                // on `lookup`/arity alone, mirroring the List/Set `containsSymbol` helper above.
                let charSequenceSymbol = try #require(sema.types.charSequenceInterfaceSymbol)
                let stringContainsCandidates = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern("contains"),
                ])
                let stringContains = try #require(stringContainsCandidates.first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          case let .classType(classType) = sema.types.kind(of: receiverType)
                    else {
                        return false
                    }
                    return classType.classSymbol == charSequenceSymbol && signature.parameterTypes.count == 1
                })
                #expect(sema.symbols.symbol(stringContains)?.flags.contains(.operatorFunction) == true)

            }

            // === testWithIndexUsesIterableOfIndexedValueSignature ===

            do {

                let sample32Path = paths[32]

                let path = sample32Path

                let sample32Diagnostics = diagnosticsForPath(sample32Path, in: ctx)

                let withIndexSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("List"),
                    interner.intern("withIndex"),
                ]))
                let indexedValueSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("IndexedValue"),
                ]))
                let indexedValueRecord = try #require(sema.symbols.symbol(indexedValueSymbol))
                #expect(indexedValueRecord.kind == .class)
                #expect(indexedValueRecord.flags.contains(.dataType))

                let signature = try #require(sema.symbols.functionSignature(for: withIndexSymbol))
                guard case let .classType(iterableType) = sema.types.kind(of: signature.returnType) else {
                    Issue.record("Expected withIndex() to return Iterable<IndexedValue<T>>"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(iterableType.classSymbol)?.name)) == "Iterable")
                guard case let .out(elementType) = try #require(iterableType.args.first),
                      case let .classType(indexedValueType) = sema.types.kind(of: elementType)
                else {
                    Issue.record("Expected Iterable element type to be IndexedValue"); return
                }
                #expect(indexedValueType.classSymbol == indexedValueSymbol)

            }

            // === testMutableSetMutationMembersUseRuntimeExternalLinks ===

            do {

                let sample33Path = paths[33]

                let path = sample33Path

                let sample33Diagnostics = diagnosticsForPath(sample33Path, in: ctx)

                let expectedExternalLinks = [
                    "add": "kk_mutable_set_add",
                    "remove": "kk_mutable_set_remove",
                    "addAll": "kk_mutable_set_addAll",
                    "clear": "kk_mutable_set_clear",
                ]

                for (memberName, externalLinkName) in expectedExternalLinks {
                    let symbol = try #require(sema.symbols.lookup(fqName: [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("MutableSet"),
                        interner.intern(memberName),
                    ]))
                    #expect(sema.symbols.externalLinkName(for: symbol) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
                }

                let addAllSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("MutableSet"),
                    interner.intern("addAll"),
                ]))
                #expect(sema.symbols.externalLinkName(for: addAllSymbol) == "kk_mutable_set_addAll", "Expected addAll to resolve to kk_mutable_set_addAll")

            }

            // === testMutableListBulkMutationMembersUseInvariantReceiverType ===

            do {

                let sample34Path = paths[34]

                let path = sample34Path

                let sample34Diagnostics = diagnosticsForPath(sample34Path, in: ctx)

                let mutableListFQName = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("MutableList"),
                ]

                for memberName in ["addAll", "removeAll", "retainAll"] {
                    let symbol = try #require(sema.symbols.lookup(fqName: mutableListFQName + [interner.intern(memberName)]))
                    let signature = try #require(sema.symbols.functionSignature(for: symbol))
                    let receiverType = try #require(signature.receiverType)

                    guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType),
                          let firstArg = receiverClassType.args.first
                    else {
                        Issue.record("Expected MutableList.\(memberName) receiver to be a class type"); return
                    }

                    guard case .invariant = firstArg else {
                        Issue.record("Expected MutableList.\(memberName) receiver to remain invariant"); return
                    }
                }

            }

            // === testMutableSetClearIsNotMarkedOperatorFunction ===

            do {

                let sample35Path = paths[35]

                let path = sample35Path

                let sample35Diagnostics = diagnosticsForPath(sample35Path, in: ctx)

                let clearSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("MutableSet"),
                    interner.intern("clear"),
                ]))

                #expect(!(sema.symbols.symbol(clearSymbol)?.flags.contains(.operatorFunction) == true), "MutableSet.clear should not be registered as an operator function")

            }

            // === testMutableSetAddAllUsesCollectionParameterType ===

            do {

                let sample36Path = paths[36]

                let path = sample36Path

                let sample36Diagnostics = diagnosticsForPath(sample36Path, in: ctx)

                let symbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("MutableSet"),
                    interner.intern("addAll"),
                ]))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                let parameterType = try #require(signature.parameterTypes.first)

                guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                    Issue.record("Expected MutableSet.addAll to take a collection type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "Collection")
                guard case let .out(elementType) = try #require(classType.args.first),
                      case .typeParam = sema.types.kind(of: elementType)
                else {
                    Issue.record("Expected MutableSet.addAll parameter to use Collection<out E>"); return
                }

            }

            // === testMapSyntheticSymbolsHaveCorrectExternalLinkNames ===

            do {

                let sample37Path = paths[37]

                let path = sample37Path

                let source = sources[37]

                let sample37Diagnostics = diagnosticsForPath(sample37Path, in: ctx)

                let kotlinCollections = ["kotlin", "collections"].map { interner.intern($0) }
                let mapFQ = kotlinCollections + [interner.intern("Map")]
                let mutableMapFQ = kotlinCollections + [interner.intern("MutableMap")]

                // KSP-430: Map higher-order functions are source-backed in
                // MapHOF.kt, so only non-migrated Map members appear here.
                let expectedLinks: [(fqName: [InternedString], memberName: String, externalLink: String)] = [
                    (mapFQ, "containsKey", "kk_map_contains_key"),
                    (mapFQ, "containsValue", "kk_map_contains_value"),
                    (mapFQ, "keys", "kk_map_keys"),
                    (mapFQ, "values", "kk_map_values"),
                    (mapFQ, "entries", "kk_map_entries"),
                    (mapFQ, "getValue", "kk_map_getValue"),
                    (mapFQ, "withDefault", "kk_map_withDefault"),
                    (mapFQ, "toList", "kk_map_toList"),
                    (mapFQ, "toMutableMap", "kk_map_to_mutable_map"),
                    (mutableMapFQ, "put", "kk_mutable_map_put"),
                    (mutableMapFQ, "remove", "kk_mutable_map_remove"),
                    (mutableMapFQ, "putAll", "kk_mutable_map_putAll"),
                ]

                for (ownerFQ, memberName, expectedExternal) in expectedLinks {
                    let memberFQ = ownerFQ + [interner.intern(memberName)]
                    let symbolID = try #require(sema.symbols.lookup(fqName: memberFQ))
                    #expect(sema.symbols.externalLinkName(for: symbolID) == expectedExternal, "Expected \(memberName) to have external link \(expectedExternal)")
                }

            }

            // === testMapWithDefaultSurfaceResolvesDefaultLambda ===

            do {

                let sample38Path = paths[38]

                let path = sample38Path

                let sample38Diagnostics = diagnosticsForPath(sample38Path, in: ctx)

                #expect(!(sample38Diagnostics.contains { $0.severity == .error }), "Expected Map.withDefault surface to resolve: \(sample38Diagnostics.map(\.message))")

            }

            // === testIndexedAndAggregateListMembersAreInlineSynthetic ===

            do {

                let sample39Path = paths[39]

                let path = sample39Path

                let source = sources[39]

                let sample39Diagnostics = diagnosticsForPath(sample39Path, in: ctx)

                let listFQName: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("List"),
                ]

                // forEachIndexed remains synthetic; mapIndexed / filterIndexed / sumOf are bundled source.
                for memberName in ["forEachIndexed"] {
                    let symbolID = try #require(sema.symbols.lookup(fqName: listFQName + [interner.intern(memberName)]))
                    let flags = try #require(sema.symbols.symbol(symbolID)?.flags)
                    #expect(flags.contains(.inlineFunction), "Expected \(memberName) to be inline")
                    #expect(flags.contains(.synthetic), "Expected \(memberName) to be synthetic")
                }

            }

            // === testListFilterIndexedUsesBundledSource ===

            do {

                let sample40Path = paths[40]

                let path = sample40Path

                let sample40Diagnostics = diagnosticsForPath(sample40Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: sample40Diagnostics)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample40Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "filterIndexed"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                #expect(sema.symbols.symbol(chosenCallee)?.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("filterIndexed"),
                ])

            }

            // === testListFilterIsInstanceUsesBundledSource ===

            do {

                let sample41Path = paths[41]

                let path = sample41Path

                let sample41Diagnostics = diagnosticsForPath(sample41Path, in: ctx)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample41Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "filterIsInstance"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                #expect(sema.symbols.symbol(chosenCallee)?.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("filterIsInstance"),
                ])

            }

            // === testListFilterHOFsUseBundledSourceCalls ===

            do {

                let sample42Path = paths[42]

                let path = sample42Path

                let sample42Diagnostics = diagnosticsForPath(sample42Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: sample42Diagnostics)

                for name in ["filter", "filterNot", "filterNotNull", "filterIndexed", "filterIsInstance"] {
                    let callExpr = try #require(memberCallExprIDsInPath(named: name, in: ast, path: sample42Path, ctx: ctx, interner: interner).last)
                    let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                    #expect(sema.symbols.symbol(chosenCallee)?.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern(name),
                    ])
                }

            }

            // === testMapHigherOrderMembersAreInlineAndToListPreservesPairType ===

            do {

                let sample43Path = paths[43]

                let path = sample43Path

                let source = sources[43]

                let sample43Diagnostics = diagnosticsForPath(sample43Path, in: ctx)

                let packageFQName: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                ]
                let mapFQName = packageFQName + [interner.intern("Map")]

                func nominalOwnerFQName(for typeID: TypeID) -> [InternedString]? {
                    switch sema.types.kind(of: sema.types.makeNonNullable(typeID)) {
                    case let .classType(classType):
                        return sema.symbols.symbol(classType.classSymbol)?.fqName
                    default:
                        return nil
                    }
                }

                for memberName in ["forEach", "map", "filter", "mapValues", "mapValuesTo", "mapKeys", "mapKeysTo"] {
                    let candidates = sema.symbols.lookupAll(fqName: packageFQName + [interner.intern(memberName)]).filter { symbolID in
                        guard let symbol = sema.symbols.symbol(symbolID),
                              symbol.kind == .function,
                              !symbol.flags.contains(.synthetic),
                              let signature = sema.symbols.functionSignature(for: symbolID),
                              let receiverType = signature.receiverType,
                              nominalOwnerFQName(for: receiverType) == mapFQName
                        else {
                            return false
                        }
                        return true
                    }
                    let symbolID = try #require(candidates.first, "Expected bundled source for Map.\(memberName)")
                    let symbol = try #require(sema.symbols.symbol(symbolID))
                    #expect(symbol.flags.contains(.inlineFunction), "Expected \(memberName) to be inline")
                    #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
                    #expect(symbol.fqName == packageFQName + [interner.intern(memberName)])
                }

                let toListSymbol = try #require(sema.symbols.lookup(fqName: mapFQName + [interner.intern("toList")]))
                let toListSignature = try #require(sema.symbols.functionSignature(for: toListSymbol))
                guard case let .classType(listType) = sema.types.kind(of: toListSignature.returnType) else {
                    Issue.record("Expected Map.toList to return List<Pair<K, V>>"); return
                }
                let listName = try #require(sema.symbols.symbol(listType.classSymbol)?.name)
                #expect(interner.resolve(listName) == "List")
                let firstListArg = try #require(listType.args.first)
                guard case let .out(pairTypeID) = firstListArg,
                      case let .classType(pairType) = sema.types.kind(of: pairTypeID)
                else {
                    Issue.record("Expected Map.toList element type to be Pair"); return
                }
                let pairName = try #require(sema.symbols.symbol(pairType.classSymbol)?.name)
                #expect(interner.resolve(pairName) == "Pair")

            }

            // === testMapEntryToPairSurfaceIsRegistered ===

            do {

                let sample44Path = paths[44]

                let path = sample44Path

                let sample44Diagnostics = diagnosticsForPath(sample44Path, in: ctx)

                #expect(!(sample44Diagnostics.contains { $0.severity == .error }), "Expected Map.Entry.toPair surface to resolve: \(sample44Diagnostics.map(\.message))")

                let entryFQName: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Map"),
                    interner.intern("Entry"),
                ]
                let toPairSymbol = try #require(sema.symbols.lookup(fqName: entryFQName + [interner.intern("toPair")]))
                #expect(sema.symbols.externalLinkName(for: toPairSymbol) == "kk_map_entry_to_pair")
                let signature = try #require(sema.symbols.functionSignature(for: toPairSymbol))
                guard case let .classType(pairType) = sema.types.kind(of: signature.returnType) else {
                    Issue.record("Expected Map.Entry.toPair to return Pair<K, V>"); return
                }
                let pairName = try #require(sema.symbols.symbol(pairType.classSymbol)?.name)
                #expect(interner.resolve(pairName) == "Pair")
                #expect(pairType.args.count == 2)

            }

            // === testBuildListInfersElementTypeFromBuilderCalls ===

            do {

                let sample45Path = paths[45]

                let path = sample45Path

                let sample45Diagnostics = diagnosticsForPath(sample45Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample45Diagnostics)

                let buildListCall = try #require(firstExprIDInPath(in: ast, path: sample45Path, ctx: ctx) { _, expr in
                    guard case let .call(callee, _, _, _) = expr,
                          case let .nameRef(name, _) = ast.arena.expr(callee)
                    else { return false }
                    return interner.resolve(name) == "buildList"
                })
                let buildListType = try #require(sema.bindings.exprType(for: buildListCall))
                guard case let .classType(listType) = sema.types.kind(of: buildListType) else {
                    Issue.record("Expected buildList(...) to produce a class type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(listType.classSymbol)?.name)) == "List")
                guard case let .out(elementType) = try #require(listType.args.first) else {
                    Issue.record("Expected List element type argument"); return
                }
                #expect(elementType == sema.types.intType)

                // Use lastExprID to skip bundled stdlib's thisRef expressions
                let explicitThis = try #require(lastExprIDInPath(in: ast, path: sample45Path, ctx: ctx) { _, expr in
                    if case .thisRef = expr { return true }
                    return false
                })
                let explicitThisType = try #require(sema.bindings.exprType(for: explicitThis))
                guard case let .classType(receiverType) = sema.types.kind(of: explicitThisType) else {
                    Issue.record("Expected builder receiver to be a class type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(receiverType.classSymbol)?.name)) == "MutableList")
                guard case let .invariant(receiverElementType) = try #require(receiverType.args.first) else {
                    Issue.record("Expected MutableList element type argument"); return
                }
                #expect(receiverElementType == sema.types.intType)

            }

            // === testBuildMapInfersKeyAndValueTypesFromBuilderCalls ===

            do {

                let sample46Path = paths[46]

                let path = sample46Path

                let sample46Diagnostics = diagnosticsForPath(sample46Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample46Diagnostics)

                let buildMapCall = try #require(firstExprIDInPath(in: ast, path: sample46Path, ctx: ctx) { _, expr in
                    guard case let .call(callee, _, _, _) = expr,
                          case let .nameRef(name, _) = ast.arena.expr(callee)
                    else { return false }
                    return interner.resolve(name) == "buildMap"
                })
                let buildMapType = try #require(sema.bindings.exprType(for: buildMapCall))
                guard case let .classType(mapType) = sema.types.kind(of: buildMapType) else {
                    Issue.record("Expected buildMap(...) to produce a class type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(mapType.classSymbol)?.name)) == "Map")
                guard mapType.args.count >= 2,
                      case let .out(keyType) = mapType.args[0],
                      case let .out(valueType) = mapType.args[1]
                else {
                    Issue.record("Expected Map key/value type arguments"); return
                }
                #expect(keyType == sema.types.stringType)
                #expect(valueType == sema.types.intType)

                // Use lastExprID to skip bundled stdlib's thisRef expressions
                let explicitThis = try #require(lastExprIDInPath(in: ast, path: sample46Path, ctx: ctx) { _, expr in
                    if case .thisRef = expr { return true }
                    return false
                })
                let explicitThisType = try #require(sema.bindings.exprType(for: explicitThis))
                guard case let .classType(receiverType) = sema.types.kind(of: explicitThisType) else {
                    Issue.record("Expected builder receiver to be a class type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(receiverType.classSymbol)?.name)) == "MutableMap")
                guard receiverType.args.count >= 2,
                      case let .invariant(receiverKeyType) = receiverType.args[0],
                      case let .invariant(receiverValueType) = receiverType.args[1]
                else {
                    Issue.record("Expected MutableMap key/value type arguments"); return
                }
                #expect(receiverKeyType == sema.types.stringType)
                #expect(receiverValueType == sema.types.intType)

            }

            // === testMapKeysToResolvesWithMutableMapDestination ===

            do {

                let sample47Path = paths[47]

                let path = sample47Path

                let source = sources[47]

                let sample47Diagnostics = diagnosticsForPath(sample47Path, in: ctx)

                let diagnosticSummary = sample47Diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: " | ")
                #expect(!(sample47Diagnostics.contains { $0.severity == .error }), "Expected Map.mapKeysTo surface to resolve cleanly, got: \(diagnosticSummary)")

                let packageFQName: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                ]
                let mapFQName = packageFQName + [interner.intern("Map")]

                func nominalOwnerFQName(for typeID: TypeID) -> [InternedString]? {
                    switch sema.types.kind(of: sema.types.makeNonNullable(typeID)) {
                    case let .classType(classType):
                        return sema.symbols.symbol(classType.classSymbol)?.fqName
                    default:
                        return nil
                    }
                }

                let candidates = sema.symbols.lookupAll(fqName: packageFQName + [interner.intern("mapKeysTo")]).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          nominalOwnerFQName(for: receiverType) == mapFQName
                    else {
                        return false
                    }
                    return true
                }
                let symbol = try #require(candidates.first, "Expected bundled source for Map.mapKeysTo")
                #expect(sema.symbols.externalLinkName(for: symbol) == nil)
                #expect(sema.symbols.symbol(symbol)?.fqName == packageFQName + [interner.intern("mapKeysTo")])

                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(signature.parameterTypes.count == 2)
                #expect(signature.returnType == signature.parameterTypes[0])

            }

            // === testMapValuesToResolvesWithMutableMapDestination ===

            do {

                let sample48Path = paths[48]

                let path = sample48Path

                let source = sources[48]

                let sample48Diagnostics = diagnosticsForPath(sample48Path, in: ctx)

                let diagnosticSummary = sample48Diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: " | ")
                #expect(!(sample48Diagnostics.contains { $0.severity == .error }), "Expected Map.mapValuesTo surface to resolve cleanly, got: \(diagnosticSummary)")

                let packageFQName: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                ]
                let mapFQName = packageFQName + [interner.intern("Map")]

                func nominalOwnerFQName(for typeID: TypeID) -> [InternedString]? {
                    switch sema.types.kind(of: sema.types.makeNonNullable(typeID)) {
                    case let .classType(classType):
                        return sema.symbols.symbol(classType.classSymbol)?.fqName
                    default:
                        return nil
                    }
                }

                let candidates = sema.symbols.lookupAll(fqName: packageFQName + [interner.intern("mapValuesTo")]).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          nominalOwnerFQName(for: receiverType) == mapFQName
                    else {
                        return false
                    }
                    return true
                }
                let symbol = try #require(candidates.first, "Expected bundled source for Map.mapValuesTo")
                #expect(sema.symbols.externalLinkName(for: symbol) == nil)
                #expect(sema.symbols.symbol(symbol)?.fqName == packageFQName + [interner.intern("mapValuesTo")])

                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(signature.parameterTypes.count == 2)
                #expect(signature.returnType == signature.parameterTypes[0])

            }

            // === testMutableMapPutAllUsesProjectedMapParameterType ===

            do {

                let sample49Path = paths[49]

                let path = sample49Path

                let sample49Diagnostics = diagnosticsForPath(sample49Path, in: ctx)

                let symbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("MutableMap"),
                    interner.intern("putAll"),
                ]))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                let parameterType = try #require(signature.parameterTypes.first)

                guard case let .classType(classType) = sema.types.kind(of: parameterType) else {
                    Issue.record("Expected MutableMap.putAll to take a map type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "Map")
                guard classType.args.count == 2,
                      case let .out(keyType) = classType.args[0],
                      case let .out(valueType) = classType.args[1],
                      case .typeParam = sema.types.kind(of: keyType),
                      case .typeParam = sema.types.kind(of: valueType)
                else {
                    Issue.record("Expected MutableMap.putAll parameter to use projected Map<K, V>"); return
                }

            }

            // === testGroupingEachCountToUsesProjectedMutableMapParameterType ===

            do {

                let sample50Path = paths[50]

                let path = sample50Path

                let sample50Diagnostics = diagnosticsForPath(sample50Path, in: ctx)

                let symbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Grouping"),
                    interner.intern("eachCountTo"),
                ]))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(sema.symbols.externalLinkName(for: symbol) == "kk_grouping_eachCountTo")
                #expect(signature.parameterTypes.count == 1)
                #expect(signature.returnType == signature.parameterTypes[0])

                let receiverType = try #require(signature.receiverType)
                guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
                    Issue.record("Expected Grouping.eachCountTo receiver to be a class type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(receiverClassType.classSymbol)?.name)) == "Grouping")

                let parameterType = try #require(signature.parameterTypes.first)
                guard case let .classType(parameterClassType) = sema.types.kind(of: parameterType) else {
                    Issue.record("Expected eachCountTo to take a MutableMap type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(parameterClassType.classSymbol)?.name)) == "MutableMap")
                #expect(parameterClassType.args.count == 2)
                guard case let .in(keyProjection) = parameterClassType.args[0],
                      case .typeParam = sema.types.kind(of: keyProjection),
                      case let .invariant(valueType) = parameterClassType.args[1]
                else {
                    Issue.record("Expected eachCountTo parameter to use MutableMap<in K, Int>"); return
                }
                #expect(valueType == sema.types.intType)

            }

            // === testBuildListCapacityOverloadResolves ===

            do {

                let sample51Path = paths[51]

                let path = sample51Path

                let sample51Diagnostics = diagnosticsForPath(sample51Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample51Diagnostics)

                let buildListCall = try #require(firstExprIDInPath(in: ast, path: sample51Path, ctx: ctx) { _, expr in
                    guard case let .call(callee, _, _, _) = expr,
                          case let .nameRef(name, _) = ast.arena.expr(callee)
                    else { return false }
                    return interner.resolve(name) == "buildList"
                })
                let buildListType = try #require(sema.bindings.exprType(for: buildListCall))
                guard case let .classType(listType) = sema.types.kind(of: buildListType) else {
                    Issue.record("Expected buildList(capacity) to produce a class type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(listType.classSymbol)?.name)) == "List")
                guard case let .out(elementType) = try #require(listType.args.first) else {
                    Issue.record("Expected List element type argument"); return
                }
                #expect(elementType == sema.types.intType)

            }

            // === testListZipWithNextOverloadsInferReturnTypes ===

            do {

                let sample52Path = paths[52]

                let path = sample52Path

                let sample52Diagnostics = diagnosticsForPath(sample52Path, in: ctx)

                #expect(sample52Diagnostics.isEmpty, "Expected List.zipWithNext overloads to type-check cleanly, got: \(sample52Diagnostics)")

                func projectedType(_ projection: TypeArg) -> TypeID? {
                    switch projection {
                    case let .invariant(type), let .out(type), let .in(type):
                        return type
                    case .star:
                        return nil
                    }
                }

                let noArgCall = try #require(firstExprIDInPath(in: ast, path: sample52Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return interner.resolve(callee) == "zipWithNext" && args.isEmpty
                })
                let transformCall = try #require(firstExprIDInPath(in: ast, path: sample52Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return interner.resolve(callee) == "zipWithNext" && args.count == 1
                })

                let noArgType = try #require(sema.bindings.exprType(for: noArgCall))
                guard case let .classType(noArgListType) = sema.types.kind(of: noArgType),
                      let pairType = projectedType(try #require(noArgListType.args.first)),
                      case let .classType(pairClassType) = sema.types.kind(of: pairType)
                else {
                    Issue.record("Expected zipWithNext() to return List<Pair<Int, Int>>"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(noArgListType.classSymbol)?.name)) == "List")
                #expect(try interner.resolve(#require(sema.symbols.symbol(pairClassType.classSymbol)?.name)) == "Pair")
                #expect(pairClassType.args.compactMap(projectedType) == [sema.types.intType, sema.types.intType])

                let transformType = try #require(sema.bindings.exprType(for: transformCall))
                guard case let .classType(transformListType) = sema.types.kind(of: transformType),
                      let transformElementType = projectedType(try #require(transformListType.args.first))
                else {
                    Issue.record("Expected zipWithNext(transform) to return List<Int>"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(transformListType.classSymbol)?.name)) == "List")
                #expect(transformElementType == sema.types.intType)

            }

            // === testListZipUsesRuntimeExternalLinkAndReturnsPairList ===

            do {

                let sample53Path = paths[53]

                let path = sample53Path

                let sample53Diagnostics = diagnosticsForPath(sample53Path, in: ctx)

                #expect(sample53Diagnostics.isEmpty, "Expected List.zip to type-check cleanly, got: \(sample53Diagnostics)")

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample53Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return interner.resolve(callee) == "zip" && args.count == 1
                })

                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                let fileID = try #require(sema.symbols.sourceFileID(for: chosenCallee))
                #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/ListWindowChunk.kt")

                let callType = try #require(sema.bindings.exprType(for: callExpr))
                guard case let .classType(listType) = sema.types.kind(of: callType) else {
                    Issue.record("Expected List.zip to return a List type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(listType.classSymbol)?.name)) == "List")
                let pairType: TypeID
                switch try #require(listType.args.first) {
                case let .invariant(type), let .out(type), let .in(type):
                    pairType = type
                case .star:
                    Issue.record("Expected List.zip to return a concrete Pair projection"); return
                }
                guard case let .classType(pairClassType) = sema.types.kind(of: pairType) else {
                    Issue.record("Expected List.zip to return List<Pair<Int, String>>, got \(sema.types.kind(of: pairType))"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(pairClassType.classSymbol)?.name)) == "Pair")
                #expect(pairClassType.args.count == 2)

                let firstArgument: TypeID
                switch pairClassType.args[0] {
                case let .invariant(type), let .out(type), let .in(type):
                    firstArgument = type
                case .star:
                    Issue.record("Expected concrete Pair first argument"); return
                }
                let secondArgument: TypeID
                switch pairClassType.args[1] {
                case let .invariant(type), let .out(type), let .in(type):
                    secondArgument = type
                case .star:
                    Issue.record("Expected concrete Pair second argument"); return
                }
                #expect(firstArgument == sema.types.intType)
                #expect(secondArgument == sema.types.stringType)

            }

            // === testListFlatMapIndexedBindsToBundledSource ===

            do {

                let sample54Path = paths[54]

                let path = sample54Path

                let source = sources[54]

                let sample54Diagnostics = diagnosticsForPath(sample54Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample54Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sample54Diagnostics)

                let sourceFQName = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("flatMapIndexed"),
                ]
                let symbols = sema.symbols.lookupAll(fqName: sourceFQName)
                let listFlatMapIndexedSymbol = try #require(symbols.first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          let (receiverClassType, _) = resolveClassTypeSymbol(receiverType, sema: sema),
                          let receiverSymbol = sema.symbols.symbol(receiverClassType.classSymbol)
                    else { return false }
                    return interner.resolve(receiverSymbol.name) == "List"
                }, "Expected bundled source List.flatMapIndexed overload")

                let symbolInfo = try #require(sema.symbols.symbol(listFlatMapIndexedSymbol))
                #expect(!symbolInfo.flags.contains(.synthetic), "flatMapIndexed must be a bundled source declaration")
                #expect(sema.symbols.externalLinkName(for: listFlatMapIndexedSymbol) == nil, "source flatMapIndexed must not link to runtime")

                let symbol = listFlatMapIndexedSymbol
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType),
                      let returnSymbol = sema.symbols.symbol(returnClassType.classSymbol)
                else {
                    Issue.record("Expected List.flatMapIndexed to return List<R>"); return
                }
                #expect(interner.resolve(returnSymbol.name) == "List")

                let transformType = try #require(signature.parameterTypes.first)
                guard case let .functionType(functionType) = sema.types.kind(of: transformType),
                      let (_, transformReturnSymbol) = resolveClassTypeSymbol(functionType.returnType, sema: sema)
                else {
                    Issue.record("Expected List.flatMapIndexed transform to return List<R>"); return
                }
                #expect(functionType.params.count == 2, "Expected flatMapIndexed transform to take (index, element)")
                #expect(functionType.params.first == sema.types.intType)
                #expect(functionType.params.last != sema.types.intType, "Second transform parameter should be the list element type, not Int")
                #expect(interner.resolve(transformReturnSymbol.name) == "List")

            }

            // === testListToBooleanArrayUsesRuntimeExternalLink ===

            do {

                let sample55Path = paths[55]

                let path = sample55Path

                let sample55Diagnostics = diagnosticsForPath(sample55Path, in: ctx)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample55Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "toBooleanArray"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_toBooleanArray")
                let resultType = try #require(sema.bindings.exprTypes[callExpr])
                guard case let .classType(classType) = sema.types.kind(of: resultType),
                      let symbol = sema.symbols.symbol(classType.classSymbol)
                else {
                    Issue.record("Expected toBooleanArray to return BooleanArray"); return
                }
                #expect(interner.resolve(symbol.name) == "BooleanArray")

            }

            // === testListToShortArrayUsesRuntimeExternalLink ===

            do {

                let sample56Path = paths[56]

                let path = sample56Path

                let sample56Diagnostics = diagnosticsForPath(sample56Path, in: ctx)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample56Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "toShortArray"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_toShortArray")
                let resultType = try #require(sema.bindings.exprTypes[callExpr])
                guard case let .classType(classType) = sema.types.kind(of: resultType),
                      let symbol = sema.symbols.symbol(classType.classSymbol)
                else {
                    Issue.record("Expected toShortArray to return ShortArray"); return
                }
                #expect(interner.resolve(symbol.name) == "ShortArray")

            }

            // === testListToDoubleArrayUsesRuntimeExternalLink ===

            do {

                let sample57Path = paths[57]

                let path = sample57Path

                let sample57Diagnostics = diagnosticsForPath(sample57Path, in: ctx)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample57Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "toDoubleArray"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_toDoubleArray")
                let resultType = try #require(sema.bindings.exprTypes[callExpr])
                guard case let .classType(classType) = sema.types.kind(of: resultType),
                      let symbol = sema.symbols.symbol(classType.classSymbol)
                else {
                    Issue.record("Expected toDoubleArray to return DoubleArray"); return
                }
                #expect(interner.resolve(symbol.name) == "DoubleArray")

            }

            // === testListToFloatArrayUsesRuntimeExternalLink ===

            do {

                let sample58Path = paths[58]

                let path = sample58Path

                let sample58Diagnostics = diagnosticsForPath(sample58Path, in: ctx)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample58Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "toFloatArray"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_toFloatArray")
                let resultType = try #require(sema.bindings.exprTypes[callExpr])
                guard case let .classType(classType) = sema.types.kind(of: resultType),
                      let symbol = sema.symbols.symbol(classType.classSymbol)
                else {
                    Issue.record("Expected toFloatArray to return FloatArray"); return
                }
                #expect(interner.resolve(symbol.name) == "FloatArray")

            }

        }
    }

}

#endif
