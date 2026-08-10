#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ListSyntheticMemberLinkTests {

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
    func testRunFrontendClean() throws {

        let sources: [String] = [
            // testListMaxOrNullAndMinOrNullRequireComparableElements
            """
            package sample0

                    class Box

                    fun render(values: List<Box>) {
                        values.maxOrNull()
                        values.minOrNull()
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runFrontend(ctx)
            try? SemaPhase().run(ctx)

            let interner = ctx.interner

            // === testListMaxOrNullAndMinOrNullRequireComparableElements ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let boundDiagnostics = sample0Diagnostics.filter { $0.code == "KSWIFTK-SEMA-BOUND" }
                #expect(boundDiagnostics.count == 2, "Expected bound diagnostics for maxOrNull/minOrNull")

            }

        }
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testListLastIndexExtensionPropertyResolvesToRuntimeGetter
            """
            package sample0

                    import kotlin.collections.lastIndex

                    fun last(values: List<String>): Int {
                        return values.lastIndex
                    }

            """,
            // testListTransformMembersUseRuntimeExternalLinksForParameterReceivers
            """
            package sample1

                    import kotlin.random.Random

                    fun render(values: List<Int>) {
                        values.take(3)
                        values.drop(2)
                        values.reversed()
                        values.sorted()
                        values.distinct()
                        values.shuffled()
                        values.shuffled(Random)
                    }

            """,
            // testListAndCollectionConversionMembersUseRuntimeExternalLinks
            """
            package sample2
            fun noop() {}
            """,
            // testListIndicesExtensionPropertyResolvesToRuntimeGetter
            """
            package sample3

                    import kotlin.collections.indices
                    import kotlin.ranges.IntRange

                    fun range(values: List<String>): IntRange {
                        return values.indices
                    }

            """,
            // testArrayListOfFactoryInfersMutableListType
            """
            package sample4

                    fun probe() {
                        val values = arrayListOf(1, 2)
                        values.add(3)
                        val typed: ArrayList<Int> = arrayListOf<Int>()
                        typed.add(4)
                    }

            """,
            // testLinkedSetOfFactoryInfersLinkedHashSetType
            """
            package sample5

                    fun probe() {
                        val values = linkedSetOf(1, 2)
                        values.add(3)
                        val typed: LinkedHashSet<Int> = linkedSetOf<Int>()
                        typed.add(4)
                    }

            """,
            // testLinkedHashSetConcreteClassAndConstructorSurfaceIsRegistered
            """
            package sample6

                    fun probe() {
                        val constructed: LinkedHashSet<Int> = LinkedHashSet<Int>()
                        val asMutable: MutableSet<Int> = constructed
                        val fromExpectedMutable: MutableSet<Int> = LinkedHashSet()
                        constructed.add(1)
                        asMutable.add(2)
                        fromExpectedMutable.add(3)
                    }

            """,
            // testLinkedMapOfFactoryInfersMutableMapType
            """
            package sample7

                    fun probe() {
                        val values = linkedMapOf("a" to 1)
                        values.put("b", 2)
                        val typed: LinkedHashMap<String, Int> = linkedMapOf<String, Int>()
                        typed.put("c", 3)
                    }

            """,
            // testHashMapOfFactoryInfersMutableMapType
            """
            package sample8

                    fun probe() {
                        val values = hashMapOf("a" to 1)
                        values.put("b", 2)
                        val typed: HashMap<String, Int> = hashMapOf<String, Int>()
                        typed.put("c", 3)
                    }

            """,
            // testHashSetOfFactoryInfersMutableSetType
            """
            package sample9

                    fun probe() {
                        val values = hashSetOf(1, 2)
                        values.add(3)
                        val typed: HashSet<Int> = hashSetOf<Int>()
                        typed.add(4)
                    }

            """,
            // testListAggregateMembersUseRuntimeExternalLinks
            """
            package sample10
            fun noop() {}
            """,
            // testBundledListAggregateHOFsSuppressSyntheticStubs
            """
            package sample11
            fun noop() {}
            """,
            // testListSearchHOFsHaveBundledSourceDefinitions
            """
            package sample12
            fun noop() {}
            """,
            // testListFilterIsInstanceToBindsBundledSource
            """
            package sample13

                    fun collect(values: List<Any>, dest: MutableList<String>) {
                        values.filterIsInstanceTo(dest)
                    }

            """,
            // testIterableSumByResolvesToListRuntime
            """
            package sample14

                    fun checksum(values: Iterable<Int>): Int {
                        return values.sumBy { value ->
                            value * value
                        }
                    }

                    fun checksumFromList(values: List<Int>): Int {
                        return values.sumBy(selector = { value ->
                            value * 2
                        })
                    }

            """,
            // testIterableSumByDoubleResolvesToListRuntime
            """
            package sample15

                    fun checksum(values: Iterable<Int>): Double {
                        return values.sumByDouble { value ->
                            if (value == 2) 1.5 else 0.25
                        }
                    }

                    fun checksumFromList(values: List<Int>): Double {
                        return values.sumByDouble(selector = { value ->
                            value.toDouble()
                        })
                    }

            """,
            // testIterableFirstNotNullOfResolvesInCallExpressions
            """
            package sample16

                    fun pickLabel(values: Iterable<Int>): String {
                        return values.firstNotNullOf<String> { value ->
                            if (value == 2) "two" else null
                        }
                    }

                    fun pickListLabel(values: List<Int>): String {
                        return values.firstNotNullOf<String> { value ->
                            if (value == 3) "three" else null
                        }
                    }

            """,
            // testIterableFirstNotNullOfOrNullResolvesInCallExpressions
            """
            package sample17

                    fun pickLabel(values: Iterable<Int>): String? {
                        return values.firstNotNullOfOrNull<String> { value ->
                            if (value == 2) "two" else null
                        }
                    }

                    fun pickListLabel(values: List<Int>): String? {
                        return values.firstNotNullOfOrNull<String> { value ->
                            if (value == 3) "three" else null
                        }
                    }

            """,
            // testIterableMinusElementResolvesToListRuntime
            """
            package sample18

                    fun removeValue(values: Iterable<Int>): List<Int> {
                        return values.minusElement(2)
                    }

                    fun removeFromList(values: List<Int>): List<Int> {
                        return values.minusElement(element = 3)
                    }

            """,
            // testIterableReduceRightIndexedResolvesToListRuntime
            """
            package sample19

                    fun checksum(values: Iterable<Int>): Int {
                        return values.reduceRightIndexed { index, value, acc ->
                            index * 100 + value * 10 + acc
                        }
                    }

                    fun checksumFromList(values: List<Int>): Int {
                        return values.reduceRightIndexed(operation = { index, value, acc ->
                            index + value + acc
                        })
                    }

            """,
            // testIterableReduceRightIndexedOrNullResolvesToListRuntime
            """
            package sample20

                    fun checksum(values: Iterable<Int>): Int? {
                        return values.reduceRightIndexedOrNull { index, value, acc ->
                            index * 100 + value * 10 + acc
                        }
                    }

                    fun checksumFromList(values: List<Int>): Int? {
                        return values.reduceRightIndexedOrNull(operation = { index, value, acc ->
                            index + value + acc
                        })
                    }

            """,
            // testIterableReduceRightOrNullResolvesToListRuntime
            """
            package sample21

                    fun checksum(values: Iterable<Int>): Int? {
                        return values.reduceRightOrNull { value, acc ->
                            value * 10 + acc
                        }
                    }

                    fun checksumFromList(values: List<Int>): Int? {
                        return values.reduceRightOrNull(operation = { value, acc ->
                            value + acc
                        })
                    }

            """,
            // testListFirstAndOrNullTerminalsReturnElementsWithoutCollectionMarking
            """
            package sample22

                    fun probe(values: List<Int>) {
                        values.first()
                        values.firstOrNull()
                        values.firstOrNull { it > 1 }
                        values.lastOrNull()
                        values.lastOrNull { it < 3 }
                    }

            """,
            // testComparableSyntheticStubUsesContravariantTypeParameter
            """
            package sample23
            fun noop() {}
            """,
            // testCollectionFallbackRejectsListOnlyIndexedLookupsOnAbstractCollection
            """
            package sample24

                    fun firstValue(values: Collection<Int>): Int? = values.firstOrNull()
                    fun lastValue(values: Collection<Int>): Int? = values.lastOrNull()
                    fun fallbackValue(values: Collection<Int>): Int = values.getOrElse(0) { -1 }

            """,
            // testCollectionLastInfersElementType
            """
            package sample25

                    fun lastValue(values: Collection<Int>): Int = values.last()

            """,
            // testPrimitiveIteratorSurfacesAreRegistered
            """
            package sample26
            fun noop() {}
            """,
            // testPrimitiveIteratorSubclassResolvesAsIterator
            """
            package sample27

                    import kotlin.collections.IntIterator
                    import kotlin.collections.Iterator

                    class ProbeIntIterator : IntIterator() {
                        override fun hasNext(): Boolean = false
                        override fun nextInt(): Int = 42
                    }

                    fun accept(iterator: Iterator<Int>) {}

                    fun probe(iterator: ProbeIntIterator): Int {
                        accept(iterator)
                        return iterator.nextInt() + iterator.next()
                    }

            """,
            // testAbstractIteratorSurfaceIsRegistered
            """
            package sample28
            fun noop() {}
            """,
            // testAbstractIteratorSubclassProtectedMembersResolve
            """
            package sample29

                    import kotlin.collections.AbstractIterator
                    import kotlin.collections.Iterator

                    class OneShotIterator(private val value: Int) : AbstractIterator<Int>() {
                        override fun computeNext() {
                            setNext(value)
                            done()
                        }
                    }

                    fun accept(iterator: Iterator<Int>) {}

                    fun probe(iterator: OneShotIterator) {
                        accept(iterator)
                    }

            """,
            // testAbstractCollectionSurfaceIsRegistered
            """
            package sample30
            fun noop() {}
            """,
            // testAbstractCollectionCanBeUsedAsCollectionSupertype
            """
            package sample31

                    import kotlin.collections.AbstractCollection
                    import kotlin.collections.Collection

                    abstract class ProbeCollection : AbstractCollection<Int>()

                    fun accept(values: Collection<Int>) {}

                    fun probe(values: ProbeCollection) {
                        accept(values)
                    }

            """,
            // testAbstractListSurfaceIsRegistered
            """
            package sample32
            fun noop() {}
            """,
            // testAbstractSetSurfaceIsRegistered
            """
            package sample33
            fun noop() {}
            """,
            // testAbstractListCanBeUsedAsListSupertype
            """
            package sample34

                    import kotlin.collections.AbstractList
                    import kotlin.collections.Collection
                    import kotlin.collections.List

                    abstract class ProbeList : AbstractList<Int>()

                    fun acceptCollection(values: Collection<Int>) {}
                    fun acceptList(values: List<Int>) {}

                    fun probe(values: ProbeList) {
                        acceptCollection(values)
                        acceptList(values)
                        values[0]
                        values.listIterator()
                    }

            """,
            // testAbstractSetCanBeUsedAsCollectionAndSetSupertype
            """
            package sample35

                    import kotlin.collections.AbstractSet
                    import kotlin.collections.Collection
                    import kotlin.collections.Set

                    abstract class ProbeSet : AbstractSet<Int>()

                    fun acceptCollection(values: Collection<Int>) {}
                    fun acceptSet(values: Set<Int>) {}

                    fun probe(values: ProbeSet) {
                        acceptCollection(values)
                        acceptSet(values)
                        values.contains(1)
                        values.isEmpty()
                    }

            """,
            // testRandomAccessMarkerInterfaceSurfaceIsRegistered
            """
            package sample36

                    import kotlin.collections.RandomAccess

                    class IndexedBag : RandomAccess

                    fun keepRandomAccess(marker: RandomAccess): RandomAccess {
                        return marker
                    }

                    fun probe(value: IndexedBag): RandomAccess {
                        return keepRandomAccess(value)
                    }

            """,
            // testAbstractMutableCollectionSurfaceIsRegistered
            """
            package sample37
            fun noop() {}
            """,
            // testAbstractMutableCollectionCanBeUsedAsMutableCollectionSupertype
            """
            package sample38

                    import kotlin.collections.AbstractMutableCollection
                    import kotlin.collections.Collection
                    import kotlin.collections.MutableCollection

                    abstract class ProbeMutableCollection : AbstractMutableCollection<Int>()

                    fun acceptReadonly(values: Collection<Int>) {}
                    fun acceptMutable(values: MutableCollection<Int>) {}

                    fun probe(values: ProbeMutableCollection) {
                        acceptReadonly(values)
                        acceptMutable(values)
                    }

            """,
            // testAbstractMutableSetSurfaceIsRegistered
            """
            package sample39
            fun noop() {}
            """,
            // testAbstractMutableMapSurfaceIsRegistered
            """
            package sample40
            fun noop() {}
            """,
            // testAbstractMutableSetCanBeUsedAsSetAndMutableSetSupertype
            """
            package sample41

                    import kotlin.collections.AbstractMutableSet
                    import kotlin.collections.Set
                    import kotlin.collections.MutableSet

                    class ProbeMutableSet : AbstractMutableSet<Int>()

                    fun acceptReadonly(values: Set<Int>) {}
                    fun acceptMutable(values: MutableSet<Int>) {}

                    fun probe(values: ProbeMutableSet) {
                        acceptReadonly(values)
                        acceptMutable(values)
                    }

            """,
            // testAbstractMutableMapCanBeUsedAsMapAndMutableMapSupertype
            """
            package sample42

                    import kotlin.collections.AbstractMutableMap
                    import kotlin.collections.Map
                    import kotlin.collections.MutableMap

                    class ProbeMutableMap : AbstractMutableMap<String, Int>()

                    fun acceptReadonly(values: Map<String, Int>) {}
                    fun acceptMutable(values: MutableMap<String, Int>) {}

                    fun probe(values: ProbeMutableMap) {
                        acceptReadonly(values)
                        acceptMutable(values)
                    }

            """,
            // testMutableListIteratorSurfaceIsRegistered
            """
            package sample43
            fun noop() {}
            """,
            // testMutableIterableSurfaceIsRegistered
            """
            package sample44
            fun noop() {}
            """,
            // testMutableListIteratorMembersResolveFromMutableList
            """
            package sample45

                    fun probe(values: MutableList<Int>) {
                        val iterator = values.listIterator()
                        iterator.add(1)
                        iterator.set(2)
                        iterator.remove()
                        iterator.hasPrevious()
                        iterator.previous()
                    }

            """,
            // testMutableIterableSubtypeResolution
            """
            package sample46

                    import kotlin.collections.Iterable
                    import kotlin.collections.MutableIterable
                    import kotlin.collections.MutableList
                    import kotlin.collections.MutableSet

                    abstract class ProbeMutableIterable : MutableIterable<Int>

                    fun acceptIterable(values: Iterable<Int>) {}
                    fun acceptMutableIterable(values: MutableIterable<Int>) {}

                    fun probeIterable(values: ProbeMutableIterable) {
                        acceptIterable(values)
                        acceptMutableIterable(values)
                        values.iterator().remove()
                    }

                    fun probeList(values: MutableList<Int>) {
                        acceptMutableIterable(values)
                    }

                    fun probeSet(values: MutableSet<Int>) {
                        acceptMutableIterable(values)
                    }

            """,
            // testSetFallbackRejectsListOnlyIndexedLookups
            """
            package sample47

                    fun firstValue(values: Set<Int>): Int? = values.firstOrNull()
                    fun lastValue(values: Set<Int>): Int? = values.lastOrNull()
                    fun fallbackValue(values: Set<Int>): Int = values.getOrElse(0) { -1 }

            """,
            // testCollectionFallbackResolvesTrailingLambdaIndexedLookups
            """
            package sample48

                    fun probe(): Int {
                        val list = listOf(1, 2, 3)
                        val listValue = list.getOrElse(5) { -1 }
                        val map = mapOf("a" to 1, "b" to 2)
                        val mapValue = map.getOrElse("z") { 99 }
                        val mutableMap = mutableMapOf("a" to 1, "b" to 2)
                        val mutableValue = mutableMap.getOrPut("c") { 3 }
                        return listValue + mapValue + mutableValue
                    }

            """,
            // testMapGetOrElseAssignsLambdaExpectedTypeToLambdaArgument
            """
            package sample49

                    fun useMapDefault(values: Map<String, Int>): Int {
                        return values.getOrElse("z") { 99 }
                    }

            """,
            // testListBinarySearchHasComparableElementUpperBound
            """
            package sample50
            fun noop() {}
            """,
            // testListBinarySearchComparatorOverloadHasDefaultedRange
            """
            package sample51
            fun noop() {}
            """,
            // testListBinarySearchByUsesComparableKeyAndRuntimeOverloads
            """
            package sample52

                    data class Person(val name: String, val age: Int)

                    fun render(values: List<Person>) {
                        values.binarySearchBy(35) { it.age }
                        values.binarySearchBy(35, 1) { it.age }
                        values.binarySearchBy(35, 1, 4) { it.age }
                    }

            """,
            // testListToTypeArrayUsesTypedArrayRuntimeExternalLink
            """
            package sample53

                    fun convert(values: List<String>) {
                        val converted: Array<String> = values.toTypedArray()
                        converted.size
                    }

            """,
            // testIterableLocalVariableFromNonFactoryFunctionResolvesFilterAndCount
            """
            package sample54

                    fun getStrings(): List<String> = listOf("a", "bb", "ccc")

                    fun checksum(): Int {
                        val parts = getStrings()
                        val iter: Iterable<String> = parts
                        val filtered = iter.filter { it.length > 1 }
                        return iter.count() + filtered.size
                    }

            """,
            // testIterableParameterFromNonListLiteralArgumentResolvesFilterAndCount
            """
            package sample55

                    fun checksum(values: Iterable<Int>): Int {
                        return values.filter { it > 1 }.count()
                    }

                    fun caller(): Int = checksum(listOf(1, 2, 3))

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testListLastIndexExtensionPropertyResolvesToRuntimeGetter ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(sample0Diagnostics.isEmpty, "Expected List.lastIndex to type-check cleanly, got: \(sample0Diagnostics)")

                let propertyExpr = try #require(firstExprIDInPath(in: ast, path: sample0Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return interner.resolve(callee) == "lastIndex" && args.isEmpty
                })
                #expect(sema.bindings.exprType(for: propertyExpr) == sema.types.intType)

                let getter = try #require(sema.bindings.callBinding(for: propertyExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: getter) == "kk_list_lastIndex")

                let property = try #require(sema.bindings.identifierSymbol(for: propertyExpr))
                #expect(sema.symbols.externalLinkName(for: property) == "kk_list_lastIndex")
                #expect(sema.symbols.propertyType(for: property) == sema.types.intType)

            }

            // === testListTransformMembersUseRuntimeExternalLinksForParameterReceivers ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let expectedExternalLinks = [
                    ("take", 1, "kk_list_take" as String?),
                    ("drop", 1, "kk_list_drop" as String?),
                    ("reversed", 0, "kk_list_reversed" as String?),
                    ("sorted", 0, "kk_list_sorted" as String?),
                    ("distinct", 0, "kk_list_distinct" as String?),
                    ("shuffled", 0, "kk_list_shuffled" as String?),
                    ("shuffled", 1, "kk_list_shuffled_random" as String?),
                ]

                for (memberName, argumentCount, externalLinkName) in expectedExternalLinks {
                    let callExpr = try #require(firstExprIDInPath(in: ast, path: sample1Path, ctx: ctx) { id, expr in
                        guard case let .memberCall(_, callee, _, args, range) = expr else { return false }
                        guard interner.resolve(callee) == memberName && args.count == argumentCount else { return false }
                        guard !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_") else { return false }
                        return true
                    })
                    let binding = sema.bindings.callBinding(for: callExpr)
                    let chosenCallee = try #require(binding?.chosenCallee)
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName ?? "nil")")
                }

            }

            // === testListAndCollectionConversionMembersUseRuntimeExternalLinks ===

            do {

                let sample2Path = paths[2]

                let source = sources[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let cases: [SyntheticMemberCallCase] = [
                    .init(
                        source: """
                        fun copy(values: List<Pair<String, Int>>) {
                            values.toMap()
                        }
                        """,
                        memberName: "toMap",
                        expectedExternalLink: "kk_list_toMap",
                        expectedTypeShape: .classNamed("Map")
                    ),
                    .init(
                        source: """
                        fun copy(values: Collection<String>): List<String> {
                            return values.toList()
                        }
                        """,
                        memberName: "toList",
                        expectedExternalLink: "kk_collection_toList",
                        expectedTypeShape: .classNamed("List")
                    ),
                    .init(
                        source: """
                        fun copy(values: List<String>): MutableSet<String> {
                            return values.toHashSet()
                        }
                        """,
                        memberName: "toHashSet",
                        expectedExternalLink: "kk_list_toHashSet",
                        expectedTypeShape: nil
                    ),
                ]

                for testCase in cases {
                    try assertSyntheticMemberCall(testCase)
                }

            }

            // === testListIndicesExtensionPropertyResolvesToRuntimeGetter ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                #expect(sample3Diagnostics.isEmpty, "Expected List.indices to type-check cleanly, got: \(sample3Diagnostics)")

                let propertyExpr = try #require(firstExprIDInPath(in: ast, path: sample3Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return interner.resolve(callee) == "indices" && args.isEmpty
                })
                let propertyType = try #require(sema.bindings.exprType(for: propertyExpr))
                guard case let .classType(rangeType) = sema.types.kind(of: propertyType) else {
                    Issue.record("Expected List.indices to have IntRange type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(rangeType.classSymbol)?.name)) == "IntRange")

                let getter = try #require(sema.bindings.callBinding(for: propertyExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: getter) == "kk_list_indices")

                let property = try #require(sema.bindings.identifierSymbol(for: propertyExpr))
                #expect(sema.symbols.externalLinkName(for: property) == "kk_list_indices")
                #expect(sema.symbols.propertyType(for: property) == propertyType)

            }

            // === testArrayListOfFactoryInfersMutableListType ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                #expect(sample4Diagnostics.isEmpty, "Expected arrayListOf factory calls to type-check cleanly, got: \(sample4Diagnostics)")

                let arrayListCall = try #require(firstExprIDInPath(in: ast, path: sample4Path, ctx: ctx) { _, expr in
                    guard case let .call(callee, _, _, _) = expr,
                          case let .nameRef(name, _) = ast.arena.expr(callee)
                    else { return false }
                    return interner.resolve(name) == "arrayListOf"
                })
                let callType = try #require(sema.bindings.exprTypes[arrayListCall])
                guard case let .classType(classType) = sema.types.kind(of: callType) else {
                    Issue.record("Expected arrayListOf to produce a MutableList class type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "MutableList")
                #expect(classType.args == [.invariant(sema.types.intType)])
                #expect(sema.bindings.isCollectionExpr(arrayListCall), "Expected arrayListOf to be tracked as a collection expression")

            }

            // === testLinkedSetOfFactoryInfersLinkedHashSetType ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                #expect(sample5Diagnostics.isEmpty, "Expected linkedSetOf factory calls to type-check cleanly, got: \(sample5Diagnostics)")

                let linkedSetCall = try #require(firstExprIDInPath(in: ast, path: sample5Path, ctx: ctx) { _, expr in
                    guard case let .call(callee, _, _, _) = expr,
                          case let .nameRef(name, _) = ast.arena.expr(callee)
                    else { return false }
                    return interner.resolve(name) == "linkedSetOf"
                })
                let callType = try #require(sema.bindings.exprTypes[linkedSetCall])
                guard case let .classType(classType) = sema.types.kind(of: callType) else {
                    Issue.record("Expected linkedSetOf to produce a LinkedHashSet class type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "LinkedHashSet")
                #expect(classType.args == [.invariant(sema.types.intType)])
                #expect(sema.bindings.isCollectionExpr(linkedSetCall), "Expected linkedSetOf to be tracked as a collection expression")

            }

            // === testLinkedHashSetConcreteClassAndConstructorSurfaceIsRegistered ===

            do {

                let sample6Path = paths[6]

                let path = sample6Path

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                #expect(sample6Diagnostics.isEmpty, "Expected LinkedHashSet concrete class calls to type-check cleanly, got: \(sample6Diagnostics)")

                let kotlinCollections = [interner.intern("kotlin"), interner.intern("collections")]
                let linkedHashSetFQ = kotlinCollections + [interner.intern("LinkedHashSet")]
                let mutableSetFQ = kotlinCollections + [interner.intern("MutableSet")]
                let linkedHashSetSymbol = try #require(sema.symbols.lookup(fqName: linkedHashSetFQ))
                let mutableSetSymbol = try #require(sema.symbols.lookup(fqName: mutableSetFQ))

                let linkedHashSetInfo = try #require(sema.symbols.symbol(linkedHashSetSymbol))
                #expect(linkedHashSetInfo.kind == .class)
                #expect(linkedHashSetInfo.flags.contains(.synthetic))
                #expect(linkedHashSetInfo.flags.contains(.openType))
                #expect(sema.symbols.directSupertypes(for: linkedHashSetSymbol).contains(mutableSetSymbol))
                #expect(sema.types.nominalTypeParameterVariances(for: linkedHashSetSymbol) == [.invariant])

                let constructorSymbol = try #require(sema.symbols.lookup(fqName: linkedHashSetFQ + [interner.intern("<init>")]))
                let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
                #expect(constructorInfo.kind == .constructor)
                #expect(constructorInfo.visibility == .public)
                #expect(sema.symbols.externalLinkName(for: constructorSymbol) == "__kk_emptySet")
                let signature = try #require(sema.symbols.functionSignature(for: constructorSymbol))
                #expect(signature.parameterTypes.isEmpty)
                #expect(signature.typeParameterSymbols.count == 1)
                #expect(signature.classTypeParameterCount == 1)

                let constructorCall = try #require(firstExprIDInPath(in: ast, path: sample6Path, ctx: ctx) { _, expr in
                    guard case let .call(callee, _, _, _) = expr,
                          case let .nameRef(name, _) = ast.arena.expr(callee)
                    else { return false }
                    return interner.resolve(name) == "LinkedHashSet"
                })
                let callType = try #require(sema.bindings.exprTypes[constructorCall])
                guard case let .classType(classType) = sema.types.kind(of: callType) else {
                    Issue.record("Expected LinkedHashSet constructor to produce a class type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "LinkedHashSet")
                #expect(classType.args == [.invariant(sema.types.intType)])
                #expect(sema.bindings.isCollectionExpr(constructorCall), "Expected LinkedHashSet constructor to be tracked as a collection expression")

            }

            // === testLinkedMapOfFactoryInfersMutableMapType ===

            do {

                let sample7Path = paths[7]

                let path = sample7Path

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                #expect(sample7Diagnostics.isEmpty, "Expected linkedMapOf factory calls to type-check cleanly, got: \(sample7Diagnostics)")

                let linkedMapCall = try #require(firstExprIDInPath(in: ast, path: sample7Path, ctx: ctx) { _, expr in
                    guard case let .call(callee, _, _, _) = expr,
                          case let .nameRef(name, _) = ast.arena.expr(callee)
                    else { return false }
                    return interner.resolve(name) == "linkedMapOf"
                })
                let callType = try #require(sema.bindings.exprTypes[linkedMapCall])
                guard case let .classType(classType) = sema.types.kind(of: callType) else {
                    Issue.record("Expected linkedMapOf to produce a MutableMap class type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "MutableMap")
                #expect(classType.args == [.invariant(sema.types.stringType), .invariant(sema.types.intType)])
                #expect(sema.bindings.isCollectionExpr(linkedMapCall), "Expected linkedMapOf to be tracked as a collection expression")

            }

            // === testHashMapOfFactoryInfersMutableMapType ===

            do {

                let sample8Path = paths[8]

                let path = sample8Path

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                #expect(sample8Diagnostics.isEmpty, "Expected hashMapOf factory calls to type-check cleanly, got: \(sample8Diagnostics)")

                let hashMapCall = try #require(firstExprIDInPath(in: ast, path: sample8Path, ctx: ctx) { _, expr in
                    guard case let .call(callee, _, _, _) = expr,
                          case let .nameRef(name, _) = ast.arena.expr(callee)
                    else { return false }
                    return interner.resolve(name) == "hashMapOf"
                })
                let callType = try #require(sema.bindings.exprTypes[hashMapCall])
                guard case let .classType(classType) = sema.types.kind(of: callType) else {
                    Issue.record("Expected hashMapOf to produce a MutableMap class type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "MutableMap")
                #expect(classType.args == [.invariant(sema.types.stringType), .invariant(sema.types.intType)])
                #expect(sema.bindings.isCollectionExpr(hashMapCall), "Expected hashMapOf to be tracked as a collection expression")

            }

            // === testHashSetOfFactoryInfersMutableSetType ===

            do {

                let sample9Path = paths[9]

                let path = sample9Path

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                #expect(sample9Diagnostics.isEmpty, "Expected hashSetOf factory calls to type-check cleanly, got: \(sample9Diagnostics)")

                let hashSetCall = try #require(firstExprIDInPath(in: ast, path: sample9Path, ctx: ctx) { _, expr in
                    guard case let .call(callee, _, _, _) = expr,
                          case let .nameRef(name, _) = ast.arena.expr(callee)
                    else { return false }
                    return interner.resolve(name) == "hashSetOf"
                })
                let callType = try #require(sema.bindings.exprTypes[hashSetCall])
                guard case let .classType(classType) = sema.types.kind(of: callType) else {
                    Issue.record("Expected hashSetOf to produce a MutableSet class type"); return
                }
                #expect(try interner.resolve(#require(sema.symbols.symbol(classType.classSymbol)?.name)) == "MutableSet")
                #expect(classType.args == [.invariant(sema.types.intType)])
                #expect(sema.bindings.isCollectionExpr(hashSetCall), "Expected hashSetOf to be tracked as a collection expression")

            }

            // === testListAggregateMembersUseRuntimeExternalLinks ===

            do {

                let sample10Path = paths[10]

                let path = sample10Path

                let source = sources[10]

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                let expectedExternalLinks = [
                    "sum": "kk_list_sum",
                    // sumOf / minByOrNull / maxByOrNull are bundled Kotlin source (KSP-002).
                    "maxOfWith": "kk_list_maxOfWith",
                    "minOfWith": "kk_list_minOfWith",
                    "minBy": "kk_list_minBy",
                    "maxOfWithOrNull": "kk_list_maxOfWithOrNull",
                    "maxWithOrNull": "kk_list_maxWithOrNull",
                    "min": "kk_list_min",
                    "maxWith": "kk_list_maxWith",
                    "maxOrNull": "kk_list_maxOrNull",
                    "minOrNull": "kk_list_minOrNull",
                    "minOf": "kk_list_minOf",
                    "maxBy": "kk_list_maxBy",
                    "minOfWithOrNull": "kk_list_minOfWithOrNull",
                    "maxOfOrNull": "kk_list_maxOfOrNull",
                ]

                for (memberName, externalLinkName) in expectedExternalLinks {
                    let symbolID = try #require(sema.symbols.lookup(
                            fqName: [
                                interner.intern("kotlin"),
                                interner.intern("collections"),
                                interner.intern("List"),
                                interner.intern(memberName),
                            ]
                        ))
                    #expect(sema.symbols.externalLinkName(for: symbolID) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
                }

                // find / findLast are source-backed in ListSearchHOF.kt (KSP-423)
                // and therefore have no external link name.
                let collectionsPkg = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                ]
                for memberName in ["find", "findLast"] {
                    let sourceSymbols = sema.symbols.lookupAll(fqName: collectionsPkg + [interner.intern(memberName)]).filter { symbolID in
                        guard let symbol = sema.symbols.symbol(symbolID),
                              symbol.kind == .function,
                              !symbol.flags.contains(.synthetic),
                              let fileID = sema.symbols.sourceFileID(for: symbolID),
                              let signature = sema.symbols.functionSignature(for: symbolID),
                              signature.receiverType != nil
                        else {
                            return false
                        }
                        return ctx.sourceManager.path(of: fileID).hasPrefix("__bundled_")
                    }
                    #expect(!sourceSymbols.isEmpty, "Expected bundled Kotlin source for List.\(memberName)")
                    #expect(sourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil }, "List.\(memberName) should be source-backed")
                }

            }

            // === testBundledListAggregateHOFsSuppressSyntheticStubs ===

            do {

                let sample11Path = paths[11]

                let path = sample11Path

                let source = sources[11]

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                let packageFQName = ["kotlin", "collections"].map { interner.intern($0) }
                let listOwnerFQName = packageFQName + [interner.intern("List")]
                let iterableOwnerFQName = packageFQName + [interner.intern("Iterable")]

                func bundledListExtensionSymbols(named name: String, arity: Int) -> [SymbolID] {
                    let fqName = packageFQName + [interner.intern(name)]
                    return sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                        guard let symbol = sema.symbols.symbol(symbolID),
                              symbol.kind == .function,
                              !symbol.flags.contains(.synthetic),
                              let fileID = sema.symbols.sourceFileID(for: symbolID),
                              let signature = sema.symbols.functionSignature(for: symbolID),
                              signature.parameterTypes.count == arity,
                              signature.receiverType != nil
                        else {
                            return false
                        }
                        return ctx.sourceManager.path(of: fileID).hasPrefix("__bundled_")
                    }
                }

                func syntheticMemberSymbols(
                    ownerFQName: [InternedString],
                    name: String,
                    arity: Int,
                    externalLinkPrefix: String? = nil
                ) -> [SymbolID] {
                    let memberFQName = ownerFQName + [interner.intern(name)]
                    return sema.symbols.lookupAll(fqName: memberFQName).filter { symbolID in
                        guard let symbol = sema.symbols.symbol(symbolID),
                              symbol.kind == .function,
                              symbol.flags.contains(.synthetic),
                              let signature = sema.symbols.functionSignature(for: symbolID),
                              signature.parameterTypes.count == arity
                        else {
                            return false
                        }
                        if let externalLinkPrefix,
                           let link = sema.symbols.externalLinkName(for: symbolID)
                        {
                            return link.hasPrefix(externalLinkPrefix)
                        }
                        return externalLinkPrefix == nil
                    }
                }

                for name in ["count", "any", "all"] {
                    let bundled = bundledListExtensionSymbols(named: name, arity: 1)
                    #expect(!bundled.isEmpty, "Expected bundled Kotlin source for List.\(name)(predicate)")
                    for symbolID in bundled {
                        #expect(
                            sema.symbols.externalLinkName(for: symbolID) == nil,
                            "Bundled List.\(name) should not have an external link name"
                        )
                    }
                }

                for name in ["sumOf", "maxByOrNull", "minByOrNull"] {
                    let synthetic = syntheticMemberSymbols(
                        ownerFQName: listOwnerFQName,
                        name: name,
                        arity: 1,
                        externalLinkPrefix: "kk_list_"
                    )
                    #expect(
                        synthetic.isEmpty,
                        "Expected no synthetic List.\(name) stub when bundled Kotlin source exists, found \(synthetic.count)"
                    )
                }

                let sourceBackedFilters: [(name: String, arity: Int)] = [
                    ("filter", 1),
                    ("filterNot", 1),
                    ("filterNotNull", 0),
                    ("filterIndexed", 1),
                    ("filterIsInstance", 0),
                ]
                for (name, arity) in sourceBackedFilters {
                    let bundled = bundledListExtensionSymbols(named: name, arity: arity)
                    #expect(!bundled.isEmpty, "Expected bundled Kotlin source for List.\(name)")
                    #expect(
                        bundled.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                        "Bundled List.\(name) should not have an external link name"
                    )
                    let synthetic = syntheticMemberSymbols(
                        ownerFQName: listOwnerFQName,
                        name: name,
                        arity: arity,
                        externalLinkPrefix: "kk_list_"
                    )
                    #expect(
                        synthetic.isEmpty,
                        "Expected no synthetic List.\(name) stub when bundled Kotlin source exists, found \(synthetic.count)"
                    )
                }

                // KSP-423: search and predicate HOFs are source-backed.
                let sourceBackedSearchHOFs: [(name: String, arity: Int)] = [
                    ("contains", 1),
                    ("containsAll", 1),
                    ("lastIndexOf", 1),
                    ("count", 0),
                    ("count", 1),
                    ("any", 0),
                    ("any", 1),
                    ("all", 1),
                    ("none", 0),
                    ("none", 1),
                ]
                for (name, arity) in sourceBackedSearchHOFs {
                    let bundled = bundledListExtensionSymbols(named: name, arity: arity)
                    #expect(!bundled.isEmpty, "Expected bundled Kotlin source for List.\(name)(arity: \(arity))")
                    #expect(
                        bundled.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                        "Bundled List.\(name) should not have an external link name"
                    )
                    let synthetic = syntheticMemberSymbols(
                        ownerFQName: listOwnerFQName,
                        name: name,
                        arity: arity,
                        externalLinkPrefix: "kk_list_"
                    )
                    #expect(
                        synthetic.isEmpty,
                        "Expected no synthetic List.\(name)(arity: \(arity)) stub when bundled Kotlin source exists, found \(synthetic.count)"
                    )
                }

                for (name, link) in [("any", "kk_iterable_any"), ("all", "kk_iterable_all")] {
                    let synthetic = syntheticMemberSymbols(
                        ownerFQName: iterableOwnerFQName,
                        name: name,
                        arity: 1,
                        externalLinkPrefix: link
                    )
                    #expect(
                        synthetic.isEmpty,
                        "Expected no synthetic Iterable.\(name)(predicate) stub when bundled List.\(name) exists"
                    )
                }

                #expect(
                    syntheticMemberSymbols(ownerFQName: listOwnerFQName, name: "count", arity: 1).isEmpty
                )
                #expect(
                    syntheticMemberSymbols(ownerFQName: iterableOwnerFQName, name: "count", arity: 1).isEmpty
                )

            }

            // === testListSearchHOFsHaveBundledSourceDefinitions ===

            do {

                let sample12Path = paths[12]

                let path = sample12Path

                let source = sources[12]

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                let packageFQName = ["kotlin", "collections"].map { interner.intern($0) }
                let expectedArities: [String: Set<Int>] = [
                    "first": [0, 1],
                    "firstOrNull": [0, 1],
                    "last": [0, 1],
                    "lastOrNull": [0, 1],
                    "single": [0, 1],
                    "singleOrNull": [0, 1],
                    "find": [1],
                    "findLast": [1],
                    "indexOf": [1],
                    "indexOfFirst": [1],
                    "indexOfLast": [1],
                    "lastIndexOf": [1],
                    "contains": [1],
                    "containsAll": [1],
                    "count": [0, 1],
                    "any": [0, 1],
                    "all": [1],
                    "none": [0, 1],
                ]

                for (name, arities) in expectedArities {
                    let fqName = packageFQName + [interner.intern(name)]
                    let sourceSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                        guard let symbol = sema.symbols.symbol(symbolID),
                              symbol.kind == .function,
                              !symbol.flags.contains(.synthetic),
                              let fileID = sema.symbols.sourceFileID(for: symbolID)
                        else {
                            return false
                        }
                        let path = ctx.sourceManager.path(of: fileID)
                        return path.hasPrefix("__bundled_")
                    }
                    let registeredArities = Set(sourceSymbols.compactMap { symbolID in
                        sema.symbols.functionSignature(for: symbolID)?.parameterTypes.count
                    })
                    #expect(arities.isSubset(of: registeredArities), "Expected \(name) bundled source overloads \(arities), got \(registeredArities)")
                    #expect(sourceSymbols.allSatisfy { symbolID in
                            sema.symbols.functionSignature(for: symbolID)?.receiverType != nil
                        }, "Expected \(name) bundled source definitions to be List extension functions")
                }

            }

            // === testListFilterIsInstanceToBindsBundledSource ===

            do {

                let sample13Path = paths[13]

                let path = sample13Path

                let sample13Diagnostics = diagnosticsForPath(sample13Path, in: ctx)

                #expect(sample13Diagnostics.isEmpty, "Expected List.filterIsInstanceTo to type-check cleanly, got: \(sample13Diagnostics)")

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample13Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "filterIsInstanceTo"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                #expect(sema.symbols.symbol(chosenCallee)?.declSite != nil)
                #expect(sema.bindings.isCollectionExpr(callExpr), "Expected filterIsInstanceTo result to be tracked as a collection expression")

            }

            // === testIterableSumByResolvesToListRuntime ===

            do {

                let sample14Path = paths[14]

                let path = sample14Path

                let sample14Diagnostics = diagnosticsForPath(sample14Path, in: ctx)

                let diagnosticSummary = sample14Diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: " | ")
                #expect(!(sample14Diagnostics.contains { $0.severity == .error }), "Expected Iterable.sumBy surface to resolve cleanly, got: \(diagnosticSummary)")

                let memberFQName = ["kotlin", "collections", "Iterable", "sumBy"]
                    .map { interner.intern($0) }
                let memberSymbol = try #require(sema.symbols.lookup(fqName: memberFQName))
                #expect(sema.symbols.externalLinkName(for: memberSymbol) == "kk_list_sumBy")
                #expect(sema.symbols.annotations(for: memberSymbol).contains { $0.annotationFQName == "kotlin.Deprecated" }, "Iterable.sumBy should carry Deprecated metadata")

                let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
                #expect(signature.parameterTypes.count == 1)
                guard case let .functionType(selectorType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                    Issue.record("Expected Iterable.sumBy selector parameter to be a function"); return
                }
                #expect(selectorType.params.count == 1)
                #expect(signature.returnType == sema.types.intType)

                let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                    sema.symbols.externalLinkName(for: binding.chosenCallee)
                }
                #expect(callLinks.filter { $0 == "kk_list_sumBy" }.count == 2)

            }

            // === testIterableSumByDoubleResolvesToListRuntime ===

            do {

                let sample15Path = paths[15]

                let path = sample15Path

                let sample15Diagnostics = diagnosticsForPath(sample15Path, in: ctx)

                let diagnosticSummary = sample15Diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: " | ")
                #expect(!(sample15Diagnostics.contains { $0.severity == .error }), "Expected Iterable.sumByDouble surface to resolve cleanly, got: \(diagnosticSummary)")

                let memberFQName = ["kotlin", "collections", "Iterable", "sumByDouble"]
                    .map { interner.intern($0) }
                let memberSymbol = try #require(sema.symbols.lookup(fqName: memberFQName))
                #expect(sema.symbols.externalLinkName(for: memberSymbol) == "kk_list_sumByDouble")
                #expect(sema.symbols.annotations(for: memberSymbol).contains { $0.annotationFQName == "kotlin.Deprecated" }, "Iterable.sumByDouble should carry Deprecated metadata")

                let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
                #expect(signature.parameterTypes.count == 1)
                guard case let .functionType(selectorType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                    Issue.record("Expected Iterable.sumByDouble selector parameter to be a function"); return
                }
                #expect(selectorType.params.count == 1)
                #expect(signature.returnType == sema.types.doubleType)

                let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                    sema.symbols.externalLinkName(for: binding.chosenCallee)
                }
                #expect(callLinks.filter { $0 == "kk_list_sumByDouble" }.count == 2)

            }

            // === testIterableFirstNotNullOfResolvesInCallExpressions ===

            do {

                let sample16Path = paths[16]

                let path = sample16Path

                let sample16Diagnostics = diagnosticsForPath(sample16Path, in: ctx)

                let diagnosticSummary = sample16Diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: " | ")
                #expect(!(sample16Diagnostics.contains { $0.severity == .error }), "Expected Iterable.firstNotNullOf surface to resolve cleanly, got: \(diagnosticSummary)")

                let memberFQName = ["kotlin", "collections", "Iterable", "firstNotNullOf"]
                    .map { interner.intern($0) }
                let links = Set(
                    sema.symbols.lookupAll(fqName: memberFQName)
                        .compactMap { sema.symbols.externalLinkName(for: $0) }
                )
                #expect(links.contains("kk_iterable_firstNotNullOf"))

            }

            // === testIterableFirstNotNullOfOrNullResolvesInCallExpressions ===

            do {

                let sample17Path = paths[17]

                let path = sample17Path

                let sample17Diagnostics = diagnosticsForPath(sample17Path, in: ctx)

                let diagnosticSummary = sample17Diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: " | ")
                #expect(!(sample17Diagnostics.contains { $0.severity == .error }), "Expected Iterable.firstNotNullOfOrNull surface to resolve cleanly, got: \(diagnosticSummary)")

                let memberFQName = ["kotlin", "collections", "Iterable", "firstNotNullOfOrNull"]
                    .map { interner.intern($0) }
                let links = Set(
                    sema.symbols.lookupAll(fqName: memberFQName)
                        .compactMap { sema.symbols.externalLinkName(for: $0) }
                )
                #expect(links.contains("kk_iterable_firstNotNullOfOrNull"))

            }

            // === testIterableMinusElementResolvesToListRuntime ===

            do {

                let sample18Path = paths[18]

                let path = sample18Path

                let sample18Diagnostics = diagnosticsForPath(sample18Path, in: ctx)

                let diagnosticSummary = sample18Diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: " | ")
                #expect(!(sample18Diagnostics.contains { $0.severity == .error }), "Expected Iterable.minusElement surface to resolve cleanly, got: \(diagnosticSummary)")

                let memberFQName = ["kotlin", "collections", "Iterable", "minusElement"]
                    .map { interner.intern($0) }
                let memberSymbol = try #require(sema.symbols.lookup(fqName: memberFQName))
                #expect(sema.symbols.externalLinkName(for: memberSymbol) == "kk_list_minus_element")

                let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
                guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType),
                      let returnSymbol = sema.symbols.symbol(returnClassType.classSymbol)
                else {
                    Issue.record("Expected Iterable.minusElement to return List<E>"); return
                }
                #expect(interner.resolve(returnSymbol.name) == "List")

                let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                    sema.symbols.externalLinkName(for: binding.chosenCallee)
                }
                #expect(callLinks.filter { $0 == "kk_list_minus_element" }.count == 2)

            }

            // === testIterableReduceRightIndexedResolvesToListRuntime ===

            do {

                let sample19Path = paths[19]

                let path = sample19Path

                let source = sources[19]

                let sample19Diagnostics = diagnosticsForPath(sample19Path, in: ctx)

                let diagnosticSummary = sample19Diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: " | ")
                #expect(!(sample19Diagnostics.contains { $0.severity == .error }), "Expected Iterable.reduceRightIndexed surface to resolve cleanly, got: \(diagnosticSummary)")

                let memberFQName = ["kotlin", "collections", "Iterable", "reduceRightIndexed"]
                    .map { interner.intern($0) }
                let memberSymbol = try #require(sema.symbols.lookup(fqName: memberFQName))
                #expect(sema.symbols.externalLinkName(for: memberSymbol) == "kk_list_reduceRightIndexed")

                let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
                #expect(signature.parameterTypes.count == 1)
                guard case let .functionType(operationType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                    Issue.record("Expected Iterable.reduceRightIndexed operation parameter to be a function"); return
                }
                #expect(operationType.params.count == 3)
                guard case let .primitive(indexPrimitive, indexNullability) = sema.types.kind(of: operationType.params[0]) else {
                    Issue.record("Expected first reduceRightIndexed lambda parameter to be Int"); return
                }
                #expect(indexPrimitive == .int)
                #expect(indexNullability == .nonNull)

                let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                    sema.symbols.externalLinkName(for: binding.chosenCallee)
                }
                // List.reduceRightIndexed is now source-backed; only the Iterable
                // call resolves to the retained runtime bridge.
                #expect(callLinks.filter { $0 == "kk_list_reduceRightIndexed" }.count == 1)

            }

            // === testIterableReduceRightIndexedOrNullResolvesToListRuntime ===

            do {

                let sample20Path = paths[20]

                let path = sample20Path

                let source = sources[20]

                let sample20Diagnostics = diagnosticsForPath(sample20Path, in: ctx)

                let diagnosticSummary = sample20Diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: " | ")
                #expect(!(sample20Diagnostics.contains { $0.severity == .error }), "Expected Iterable.reduceRightIndexedOrNull surface to resolve cleanly, got: \(diagnosticSummary)")

                let memberFQName = ["kotlin", "collections", "Iterable", "reduceRightIndexedOrNull"]
                    .map { interner.intern($0) }
                let memberSymbol = try #require(sema.symbols.lookup(fqName: memberFQName))
                #expect(sema.symbols.externalLinkName(for: memberSymbol) == "kk_list_reduceRightIndexedOrNull")

                let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
                #expect(signature.parameterTypes.count == 1)
                guard case let .functionType(operationType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                    Issue.record("Expected Iterable.reduceRightIndexedOrNull operation parameter to be a function"); return
                }
                #expect(operationType.params.count == 3)
                guard case let .primitive(indexPrimitive, indexNullability) = sema.types.kind(of: operationType.params[0]) else {
                    Issue.record("Expected first reduceRightIndexedOrNull lambda parameter to be Int"); return
                }
                #expect(indexPrimitive == .int)
                #expect(indexNullability == .nonNull)

                let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                    sema.symbols.externalLinkName(for: binding.chosenCallee)
                }
                // List.reduceRightIndexedOrNull is now source-backed; only the Iterable
                // call resolves to the retained runtime bridge.
                #expect(callLinks.filter { $0 == "kk_list_reduceRightIndexedOrNull" }.count == 1)

            }

            // === testIterableReduceRightOrNullResolvesToListRuntime ===

            do {

                let sample21Path = paths[21]

                let path = sample21Path

                let source = sources[21]

                let sample21Diagnostics = diagnosticsForPath(sample21Path, in: ctx)

                let diagnosticSummary = sample21Diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: " | ")
                #expect(!(sample21Diagnostics.contains { $0.severity == .error }), "Expected Iterable.reduceRightOrNull surface to resolve cleanly, got: \(diagnosticSummary)")

                let memberFQName = ["kotlin", "collections", "Iterable", "reduceRightOrNull"]
                    .map { interner.intern($0) }
                let memberSymbol = try #require(sema.symbols.lookup(fqName: memberFQName))
                #expect(sema.symbols.externalLinkName(for: memberSymbol) == "kk_list_reduceRightOrNull")

                let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
                #expect(signature.parameterTypes.count == 1)
                guard case let .functionType(operationType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                    Issue.record("Expected Iterable.reduceRightOrNull operation parameter to be a function"); return
                }
                #expect(operationType.params.count == 2)

                let callLinks = sema.bindings.callBindings.values.compactMap { binding in
                    sema.symbols.externalLinkName(for: binding.chosenCallee)
                }
                // List.reduceRightOrNull is now source-backed; only the Iterable
                // call resolves to the retained runtime bridge.
                #expect(callLinks.filter { $0 == "kk_list_reduceRightOrNull" }.count == 1)

            }

            // === testListFirstAndOrNullTerminalsReturnElementsWithoutCollectionMarking ===

            do {

                let sample22Path = paths[22]

                let path = sample22Path

                let source = sources[22]

                let sample22Diagnostics = diagnosticsForPath(sample22Path, in: ctx)

                let nullableIntType = sema.types.makeNullable(sema.types.intType)
                let expectedTerminalCalls: [(memberName: String, expectedType: TypeID)] = [
                    ("first", sema.types.intType),
                    ("firstOrNull", nullableIntType),
                    ("lastOrNull", nullableIntType),
                ]

                for (memberName, expectedType) in expectedTerminalCalls {
                    // Use lastExprID rather than firstExprID: bundled stdlib sources
                    // (injected before the fixture's own source) may already contain
                    // calls to the same member name, which would otherwise shadow the
                    // fixture's own call site.
                    let callExpr = try #require(lastExprIDInPath(in: ast, path: sample22Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                        return interner.resolve(callee) == memberName && args.isEmpty
                    })

                    #expect(sema.bindings.exprTypes[callExpr] == expectedType, "Expected \(memberName) to return the expected element type")
                    #expect(!(sema.bindings.isCollectionExpr(callExpr)), "Expected \(memberName) result to avoid collection-expression marking")
                }

                for memberName in ["firstOrNull", "lastOrNull"] {
                    let predicateCall = try #require(lastExprIDInPath(in: ast, path: sample22Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                        return interner.resolve(callee) == memberName && args.count == 1
                    })
                    guard case let .memberCall(_, _, _, args, _) = ast.arena.expr(predicateCall),
                          let predicateArg = args.first?.expr
                    else {
                        Issue.record("Expected \(memberName)(predicate) call to keep its lambda argument")
                        continue
                    }
                    #expect(!sema.bindings.isCollectionHOFLambdaExpr(predicateArg), "Expected \(memberName)(predicate) lambda to be unmarked for source-backed lowering")
                    #expect(sema.bindings.exprTypes[predicateCall] == nullableIntType, "Expected \(memberName)(predicate) to return nullable element type")
                    #expect(!(sema.bindings.isCollectionExpr(predicateCall)), "Expected \(memberName)(predicate) result to avoid collection-expression marking")
                }

            }

            // === testComparableSyntheticStubUsesContravariantTypeParameter ===

            do {

                let sample23Path = paths[23]

                let path = sample23Path

                let sample23Diagnostics = diagnosticsForPath(sample23Path, in: ctx)

                let comparableSymbol = try #require(sema.types.comparableInterfaceSymbol)
                #expect(sema.types.nominalTypeParameterVariances(for: comparableSymbol) == [.in], "Expected Comparable to be declared as Comparable<in T>")

                let comparableAny = sema.types.make(.classType(ClassType(
                    classSymbol: comparableSymbol,
                    args: [.invariant(sema.types.anyType)],
                    nullability: .nonNull
                )))
                let comparableString = sema.types.make(.classType(ClassType(
                    classSymbol: comparableSymbol,
                    args: [.invariant(sema.types.stringType)],
                    nullability: .nonNull
                )))

                #expect(sema.types.isSubtype(comparableAny, comparableString), "Expected Comparable<Any> to be a subtype of Comparable<String>")
                #expect(!(sema.types.isSubtype(comparableString, comparableAny)), "Expected Comparable<String> not to be a subtype of Comparable<Any>")

            }

            // === testCollectionFallbackRejectsListOnlyIndexedLookupsOnAbstractCollection ===

            do {

                let sample24Path = paths[24]

                let path = sample24Path

                let sample24Diagnostics = diagnosticsForPath(sample24Path, in: ctx)

                for memberName in ["firstOrNull", "lastOrNull", "getOrElse"] {
                    let callExpr = try #require(firstExprIDInPath(in: ast, path: sample24Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == memberName
                    })
                    #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == nil, "Expected Collection.\(memberName) to remain unresolved")
                }

                #expect(!(sample24Diagnostics.isEmpty), "Expected diagnostics for Collection indexed lookup fallbacks")

            }

            // === testCollectionLastInfersElementType ===

            do {

                let sample25Path = paths[25]

                let path = sample25Path

                let sample25Diagnostics = diagnosticsForPath(sample25Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample25Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sample25Diagnostics)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample25Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, range) = expr else { return false }
                    guard interner.resolve(callee) == "last" else { return false }
                    // KSP-483: bundled Stdlib/kotlin/io/Files.kt also calls
                    // List<String>.last() internally; exclude bundled call sites
                    // so this finds the user's Collection<Int>.last() call.
                    return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                })
                let type = try #require(sema.bindings.exprType(for: callExpr))
                #expect(sema.types.kind(of: type) == .primitive(.int, .nonNull))

            }

            // === testPrimitiveIteratorSurfacesAreRegistered ===

            do {

                let sample26Path = paths[26]

                let path = sample26Path

                let source = sources[26]

                let sample26Diagnostics = diagnosticsForPath(sample26Path, in: ctx)

                let collectionsPkg = ["kotlin", "collections"].map { interner.intern($0) }
                let iteratorSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("Iterator")]))
                let specs: [(className: String, nextName: String, elementType: TypeID)] = [
                    ("BooleanIterator", "nextBoolean", sema.types.booleanType),
                    ("ByteIterator", "nextByte", sema.types.intType),
                    ("ShortIterator", "nextShort", sema.types.intType),
                    ("IntIterator", "nextInt", sema.types.intType),
                    ("LongIterator", "nextLong", sema.types.longType),
                    ("FloatIterator", "nextFloat", sema.types.floatType),
                    ("DoubleIterator", "nextDouble", sema.types.doubleType),
                    ("CharIterator", "nextChar", sema.types.charType),
                ]

                for spec in specs {
                    let classFQName = collectionsPkg + [interner.intern(spec.className)]
                    let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))
                    let classInfo = try #require(sema.symbols.symbol(classSymbol))
                    // KSP-664: the primitive iterator shells are source-backed Kotlin
                    // declarations (PrimitiveIterators.kt), not synthetic stubs.
                    #expect(classInfo.kind == .class)
                    #expect(!classInfo.flags.contains(.synthetic))
                    #expect(classInfo.flags.contains(.abstractType))
                    #expect(sema.symbols.directSupertypes(for: classSymbol).contains(iteratorSymbol))
                    #expect(sema.symbols.supertypeTypeArgs(for: classSymbol, supertype: iteratorSymbol) == [.invariant(spec.elementType)])

                    let primitiveNextSymbol = try #require(sema.symbols.lookup(fqName: classFQName + [interner.intern(spec.nextName)]))
                    let primitiveNextInfo = try #require(sema.symbols.symbol(primitiveNextSymbol))
                    #expect(!primitiveNextInfo.flags.contains(.synthetic))
                    #expect(primitiveNextInfo.flags.contains(.abstractType))
                    let primitiveNextSignature = try #require(sema.symbols.functionSignature(for: primitiveNextSymbol))
                    #expect(primitiveNextSignature.parameterTypes.isEmpty)
                    #expect(primitiveNextSignature.returnType == spec.elementType)

                    let nextSymbol = try #require(sema.symbols.lookup(fqName: classFQName + [interner.intern("next")]))
                    let nextInfo = try #require(sema.symbols.symbol(nextSymbol))
                    #expect(!nextInfo.flags.contains(.synthetic))
                    #expect(nextInfo.flags.contains(.overrideMember))
                    #expect(try #require(sema.symbols.functionSignature(for: nextSymbol)).returnType == spec.elementType)
                }

            }

            // === testPrimitiveIteratorSubclassResolvesAsIterator ===

            do {

                let sample27Path = paths[27]

                let path = sample27Path

                let sample27Diagnostics = diagnosticsForPath(sample27Path, in: ctx)

                #expect(!(sample27Diagnostics.contains { $0.severity == .error }), "Expected primitive iterator subclass surface to resolve: \(sample27Diagnostics.map(\.message))")

            }

            // === testAbstractIteratorSurfaceIsRegistered ===

            do {

                let sample28Path = paths[28]

                let path = sample28Path

                let source = sources[28]

                let sample28Diagnostics = diagnosticsForPath(sample28Path, in: ctx)

                let abstractIteratorFQName = ["kotlin", "collections", "AbstractIterator"]
                    .map { interner.intern($0) }
                let abstractIteratorSymbol = try #require(sema.symbols.lookup(fqName: abstractIteratorFQName))
                let abstractIteratorInfo = try #require(sema.symbols.symbol(abstractIteratorSymbol))
                // KSP-664: AbstractIterator is a source-backed Kotlin declaration
                // (AbstractIterator.kt), not a synthetic stub.
                #expect(abstractIteratorInfo.kind == .class)
                #expect(!abstractIteratorInfo.flags.contains(.synthetic))
                #expect(abstractIteratorInfo.flags.contains(.abstractType))
                #expect(sema.types.nominalTypeParameterVariances(for: abstractIteratorSymbol) == [.invariant])

                let iteratorSymbol = try #require(sema.symbols.lookup(fqName: ["kotlin", "collections", "Iterator"].map { interner.intern($0) }))
                #expect(sema.symbols.directSupertypes(for: abstractIteratorSymbol).contains(iteratorSymbol))
                #expect(sema.types.directNominalSupertypes(for: abstractIteratorSymbol).contains(iteratorSymbol))
                #expect(sema.symbols.supertypeTypeArgs(for: abstractIteratorSymbol, supertype: iteratorSymbol).count == 1)
                #expect(sema.types.nominalSupertypeTypeArgs(for: abstractIteratorSymbol, supertype: iteratorSymbol).count == 1)

                // Source-backed members carry no `.synthetic` flag; abstract/override
                // shape comes from the Kotlin modifiers in AbstractIterator.kt.
                let expectedMembers: [(name: String, visibility: Visibility, requiredFlags: SymbolFlags, parameterCount: Int)] = [
                    ("computeNext", .protected, [.abstractType], 0),
                    ("done", .protected, [], 0),
                    ("setNext", .protected, [], 1),
                    ("hasNext", .public, [.overrideMember], 0),
                    ("next", .public, [.overrideMember], 0),
                ]
                for expected in expectedMembers {
                    let memberSymbol = try #require(sema.symbols.lookup(fqName: abstractIteratorFQName + [interner.intern(expected.name)]))
                    let memberInfo = try #require(sema.symbols.symbol(memberSymbol))
                    #expect(memberInfo.visibility == expected.visibility)
                    #expect(!memberInfo.flags.contains(.synthetic))
                    #expect(memberInfo.flags.isSuperset(of: expected.requiredFlags))
                    let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
                    #expect(signature.parameterTypes.count == expected.parameterCount)
                }

            }

            // === testAbstractIteratorSubclassProtectedMembersResolve ===

            do {

                let sample29Path = paths[29]

                let path = sample29Path

                let sample29Diagnostics = diagnosticsForPath(sample29Path, in: ctx)

                #expect(!(sample29Diagnostics.contains { $0.severity == .error }), "Expected AbstractIterator subclass surface to resolve: \(sample29Diagnostics.map(\.message))")

            }

            // === testAbstractCollectionSurfaceIsRegistered ===

            do {

                let sample30Path = paths[30]

                let path = sample30Path

                let sample30Diagnostics = diagnosticsForPath(sample30Path, in: ctx)

                let abstractCollectionFQName = ["kotlin", "collections", "AbstractCollection"]
                    .map { interner.intern($0) }
                let abstractCollectionSymbol = try #require(sema.symbols.lookup(fqName: abstractCollectionFQName))
                let abstractCollectionInfo = try #require(sema.symbols.symbol(abstractCollectionSymbol))
                #expect(abstractCollectionInfo.kind == .class)
                #expect(abstractCollectionInfo.flags.contains(.synthetic))
                #expect(abstractCollectionInfo.flags.contains(.abstractType))
                #expect(sema.types.nominalTypeParameterVariances(for: abstractCollectionSymbol) == [.out])

                let collectionSymbol = try #require(sema.symbols.lookup(fqName: ["kotlin", "collections", "Collection"].map { interner.intern($0) }))
                #expect(sema.symbols.directSupertypes(for: abstractCollectionSymbol).contains(collectionSymbol))
                #expect(sema.types.directNominalSupertypes(for: abstractCollectionSymbol).contains(collectionSymbol))
                #expect(sema.symbols.supertypeTypeArgs(for: abstractCollectionSymbol, supertype: collectionSymbol).count == 1)
                #expect(sema.types.nominalSupertypeTypeArgs(for: abstractCollectionSymbol, supertype: collectionSymbol).count == 1)

                let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractCollectionFQName + [interner.intern("<init>")]))
                let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
                #expect(constructorInfo.kind == .constructor)
                #expect(constructorInfo.visibility == .protected)
                let signature = try #require(sema.symbols.functionSignature(for: constructorSymbol))
                #expect(signature.parameterTypes.isEmpty)

            }

            // === testAbstractCollectionCanBeUsedAsCollectionSupertype ===

            do {

                let sample31Path = paths[31]

                let path = sample31Path

                let sample31Diagnostics = diagnosticsForPath(sample31Path, in: ctx)

                #expect(!(sample31Diagnostics.contains { $0.severity == .error }), "Expected AbstractCollection subclass surface to resolve: \(sample31Diagnostics.map(\.message))")

            }

            // === testAbstractListSurfaceIsRegistered ===

            do {

                let sample32Path = paths[32]

                let path = sample32Path

                let sample32Diagnostics = diagnosticsForPath(sample32Path, in: ctx)

                let collectionsPkg = ["kotlin", "collections"].map { interner.intern($0) }
                let abstractCollectionSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("AbstractCollection")]))
                let listSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("List")]))

                let abstractListFQName = collectionsPkg + [interner.intern("AbstractList")]
                let abstractListSymbol = try #require(sema.symbols.lookup(fqName: abstractListFQName))
                let abstractListInfo = try #require(sema.symbols.symbol(abstractListSymbol))
                #expect(abstractListInfo.kind == .class)
                #expect(abstractListInfo.flags.contains(.synthetic))
                #expect(abstractListInfo.flags.contains(.abstractType))
                #expect(sema.types.nominalTypeParameterVariances(for: abstractListSymbol) == [.out])

                let directSupertypes = sema.symbols.directSupertypes(for: abstractListSymbol)
                #expect(directSupertypes.contains(abstractCollectionSymbol))
                #expect(directSupertypes.contains(listSymbol))
                #expect(sema.symbols.supertypeTypeArgs(for: abstractListSymbol, supertype: abstractCollectionSymbol).count == 1)
                #expect(sema.symbols.supertypeTypeArgs(for: abstractListSymbol, supertype: listSymbol).count == 1)
                #expect(sema.types.nominalSupertypeTypeArgs(for: abstractListSymbol, supertype: abstractCollectionSymbol).count == 1)
                #expect(sema.types.nominalSupertypeTypeArgs(for: abstractListSymbol, supertype: listSymbol).count == 1)

                let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractListFQName + [interner.intern("<init>")]))
                let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
                #expect(constructorInfo.kind == .constructor)
                #expect(constructorInfo.visibility == .protected)
                #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)

            }

            // === testAbstractSetSurfaceIsRegistered ===

            do {

                let sample33Path = paths[33]

                let path = sample33Path

                let sample33Diagnostics = diagnosticsForPath(sample33Path, in: ctx)

                let collectionsPkg = ["kotlin", "collections"].map { interner.intern($0) }
                let collectionSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("Collection")]))
                let setSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("Set")]))

                let abstractSetFQName = collectionsPkg + [interner.intern("AbstractSet")]
                let abstractSetSymbol = try #require(sema.symbols.lookup(fqName: abstractSetFQName))
                let abstractSetInfo = try #require(sema.symbols.symbol(abstractSetSymbol))
                #expect(abstractSetInfo.kind == .class)
                #expect(abstractSetInfo.flags.contains(.synthetic))
                #expect(abstractSetInfo.flags.contains(.abstractType))
                #expect(sema.types.nominalTypeParameterVariances(for: abstractSetSymbol) == [.out])

                let abstractCollectionSymbol = sema.symbols.lookup(
                    fqName: collectionsPkg + [interner.intern("AbstractCollection")]
                )
                let collectionSupertype = abstractCollectionSymbol ?? collectionSymbol
                let directSupertypes = sema.symbols.directSupertypes(for: abstractSetSymbol)
                #expect(directSupertypes.contains(collectionSupertype))
                #expect(directSupertypes.contains(setSymbol))
                #expect(sema.symbols.supertypeTypeArgs(for: abstractSetSymbol, supertype: collectionSupertype).count == 1)
                #expect(sema.symbols.supertypeTypeArgs(for: abstractSetSymbol, supertype: setSymbol).count == 1)
                #expect(sema.types.nominalSupertypeTypeArgs(for: abstractSetSymbol, supertype: collectionSupertype).count == 1)
                #expect(sema.types.nominalSupertypeTypeArgs(for: abstractSetSymbol, supertype: setSymbol).count == 1)

                let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractSetFQName + [interner.intern("<init>")]))
                let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
                #expect(constructorInfo.kind == .constructor)
                #expect(constructorInfo.visibility == .protected)
                #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)

            }

            // === testAbstractListCanBeUsedAsListSupertype ===

            do {

                let sample34Path = paths[34]

                let path = sample34Path

                let sample34Diagnostics = diagnosticsForPath(sample34Path, in: ctx)

                #expect(!(sample34Diagnostics.contains { $0.severity == .error }), "Expected AbstractList subtype surface to resolve: \(sample34Diagnostics.map(\.message))")

            }

            // === testAbstractSetCanBeUsedAsCollectionAndSetSupertype ===

            do {

                let sample35Path = paths[35]

                let path = sample35Path

                let sample35Diagnostics = diagnosticsForPath(sample35Path, in: ctx)

                #expect(!(sample35Diagnostics.contains { $0.severity == .error }), "Expected AbstractSet subtype surface to resolve: \(sample35Diagnostics.map(\.message))")

            }

            // === testRandomAccessMarkerInterfaceSurfaceIsRegistered ===

            do {

                let sample36Path = paths[36]

                let path = sample36Path

                let source = sources[36]

                let sample36Diagnostics = diagnosticsForPath(sample36Path, in: ctx)

                #expect(!(sample36Diagnostics.contains { $0.severity == .error }), "Expected RandomAccess marker interface surface to resolve: \(sample36Diagnostics.map(\.message))")

                let randomAccessFQName = ["kotlin", "collections", "RandomAccess"]
                    .map { interner.intern($0) }
                let randomAccessSymbol = try #require(sema.symbols.lookup(fqName: randomAccessFQName))
                let randomAccessInfo = try #require(sema.symbols.symbol(randomAccessSymbol))
                #expect(randomAccessInfo.kind == .interface)
                // KSP-669: `kotlin.collections.RandomAccess` is source-backed by
                // `Sources/CompilerCore/Stdlib/kotlin/collections/RandomAccess.kt`. When the
                // bundled stdlib is loaded the source declaration reuses the synthetic shell
                // symbol and clears the `.synthetic` flag, so the registered marker interface
                // is no longer synthetic.
                #expect(!randomAccessInfo.flags.contains(.synthetic))
                #expect(sema.types.nominalTypeParameterSymbols(for: randomAccessSymbol).isEmpty)

            }

            // === testAbstractMutableCollectionSurfaceIsRegistered ===

            do {

                let sample37Path = paths[37]

                let path = sample37Path

                let sample37Diagnostics = diagnosticsForPath(sample37Path, in: ctx)

                let collectionsPkg = ["kotlin", "collections"].map { interner.intern($0) }
                let collectionSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("Collection")]))
                let mutableCollectionFQName = collectionsPkg + [interner.intern("MutableCollection")]
                let mutableCollectionSymbol = try #require(sema.symbols.lookup(fqName: mutableCollectionFQName))
                #expect(sema.types.nominalTypeParameterVariances(for: mutableCollectionSymbol) == [.invariant])
                #expect(sema.symbols.directSupertypes(for: mutableCollectionSymbol).contains(collectionSymbol))
                #expect(sema.types.directNominalSupertypes(for: mutableCollectionSymbol).contains(collectionSymbol))

                let expectedMutableMembers: [(name: String, parameterCount: Int)] = [
                    ("add", 1),
                    ("addAll", 1),
                    ("clear", 0),
                    ("remove", 1),
                    ("removeAll", 1),
                    ("retainAll", 1),
                ]
                for expected in expectedMutableMembers {
                    let memberSymbol = try #require(sema.symbols.lookup(fqName: mutableCollectionFQName + [interner.intern(expected.name)]))
                    let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
                    #expect(signature.parameterTypes.count == expected.parameterCount)
                }

                let addSymbol = try #require(sema.symbols.lookup(fqName: mutableCollectionFQName + [interner.intern("add")]))
                #expect(sema.symbols.externalLinkName(for: addSymbol) == "kk_mutable_collection_add")
                let addAllSymbol = try #require(sema.symbols.lookup(fqName: mutableCollectionFQName + [interner.intern("addAll")]))
                #expect(sema.symbols.externalLinkName(for: addAllSymbol) == "kk_mutable_collection_addAll")

                let abstractMutableCollectionFQName = collectionsPkg + [interner.intern("AbstractMutableCollection")]
                let abstractMutableCollectionSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableCollectionFQName))
                let abstractMutableCollectionInfo = try #require(sema.symbols.symbol(abstractMutableCollectionSymbol))
                #expect(abstractMutableCollectionInfo.kind == .class)
                #expect(abstractMutableCollectionInfo.flags.contains(.synthetic))
                #expect(abstractMutableCollectionInfo.flags.contains(.abstractType))
                #expect(sema.types.nominalTypeParameterVariances(for: abstractMutableCollectionSymbol) == [.invariant])

                let abstractCollectionSymbol = sema.symbols.lookup(
                    fqName: collectionsPkg + [interner.intern("AbstractCollection")]
                )
                let readonlySupertype = abstractCollectionSymbol ?? collectionSymbol
                let directSupertypes = sema.symbols.directSupertypes(for: abstractMutableCollectionSymbol)
                #expect(directSupertypes.contains(readonlySupertype))
                #expect(directSupertypes.contains(mutableCollectionSymbol))
                #expect(sema.symbols.supertypeTypeArgs(
                        for: abstractMutableCollectionSymbol,
                        supertype: readonlySupertype
                    ).count == 1)
                #expect(sema.symbols.supertypeTypeArgs(
                        for: abstractMutableCollectionSymbol,
                        supertype: mutableCollectionSymbol
                    ).count == 1)

                let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableCollectionFQName + [interner.intern("<init>")]))
                let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
                #expect(constructorInfo.visibility == .protected)
                #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)

            }

            // === testAbstractMutableCollectionCanBeUsedAsMutableCollectionSupertype ===

            do {

                let sample38Path = paths[38]

                let path = sample38Path

                let sample38Diagnostics = diagnosticsForPath(sample38Path, in: ctx)

                #expect(!(sample38Diagnostics.contains { $0.severity == .error }), "Expected AbstractMutableCollection subtype surface to resolve: \(sample38Diagnostics.map(\.message))")

            }

            // === testAbstractMutableSetSurfaceIsRegistered ===

            do {

                let sample39Path = paths[39]

                let path = sample39Path

                let sample39Diagnostics = diagnosticsForPath(sample39Path, in: ctx)

                let collectionsPkg = ["kotlin", "collections"].map { interner.intern($0) }
                let setSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("Set")]))
                let mutableSetSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("MutableSet")]))
                let abstractMutableSetFQName = collectionsPkg + [interner.intern("AbstractMutableSet")]
                let abstractMutableSetSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableSetFQName))
                let abstractMutableSetInfo = try #require(sema.symbols.symbol(abstractMutableSetSymbol))
                #expect(abstractMutableSetInfo.kind == .class)
                #expect(abstractMutableSetInfo.flags.contains(.synthetic))
                #expect(abstractMutableSetInfo.flags.contains(.abstractType))
                #expect(sema.types.nominalTypeParameterVariances(for: abstractMutableSetSymbol) == [.invariant])

                let abstractSetSymbol = sema.symbols.lookup(
                    fqName: collectionsPkg + [interner.intern("AbstractSet")]
                )
                let readonlySupertype = abstractSetSymbol ?? setSymbol
                let directSupertypes = sema.symbols.directSupertypes(for: abstractMutableSetSymbol)
                #expect(directSupertypes.contains(readonlySupertype))
                #expect(directSupertypes.contains(mutableSetSymbol))
                #expect(sema.symbols.supertypeTypeArgs(for: abstractMutableSetSymbol, supertype: readonlySupertype).count == 1)
                #expect(sema.symbols.supertypeTypeArgs(for: abstractMutableSetSymbol, supertype: mutableSetSymbol).count == 1)

                let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableSetFQName + [interner.intern("<init>")]))
                let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
                #expect(constructorInfo.kind == .constructor)
                #expect(constructorInfo.visibility == .protected)
                #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)

            }

            // === testAbstractMutableMapSurfaceIsRegistered ===

            do {

                let sample40Path = paths[40]

                let path = sample40Path

                let sample40Diagnostics = diagnosticsForPath(sample40Path, in: ctx)

                let collectionsPkg = ["kotlin", "collections"].map { interner.intern($0) }
                let mapSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("Map")]))
                let mutableMapSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("MutableMap")]))
                let abstractMutableMapFQName = collectionsPkg + [interner.intern("AbstractMutableMap")]
                let abstractMutableMapSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableMapFQName))
                let abstractMutableMapInfo = try #require(sema.symbols.symbol(abstractMutableMapSymbol))
                #expect(abstractMutableMapInfo.kind == .class)
                #expect(abstractMutableMapInfo.flags.contains(.synthetic))
                #expect(abstractMutableMapInfo.flags.contains(.abstractType))
                #expect(sema.types.nominalTypeParameterVariances(for: abstractMutableMapSymbol) == [.invariant, .invariant])

                let abstractMapSymbol = sema.symbols.lookup(
                    fqName: collectionsPkg + [interner.intern("AbstractMap")]
                )
                let readonlySupertype = abstractMapSymbol ?? mapSymbol
                let directSupertypes = sema.symbols.directSupertypes(for: abstractMutableMapSymbol)
                #expect(directSupertypes.contains(readonlySupertype))
                #expect(directSupertypes.contains(mutableMapSymbol))
                #expect(sema.symbols.supertypeTypeArgs(for: abstractMutableMapSymbol, supertype: readonlySupertype).count == 2)
                #expect(sema.symbols.supertypeTypeArgs(for: abstractMutableMapSymbol, supertype: mutableMapSymbol).count == 2)

                let constructorSymbol = try #require(sema.symbols.lookup(fqName: abstractMutableMapFQName + [interner.intern("<init>")]))
                let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
                #expect(constructorInfo.kind == .constructor)
                #expect(constructorInfo.visibility == .protected)
                #expect(try #require(sema.symbols.functionSignature(for: constructorSymbol)).parameterTypes.isEmpty)

            }

            // === testAbstractMutableSetCanBeUsedAsSetAndMutableSetSupertype ===

            do {

                let sample41Path = paths[41]

                let path = sample41Path

                let sample41Diagnostics = diagnosticsForPath(sample41Path, in: ctx)

                #expect(!(sample41Diagnostics.contains { $0.severity == .error }), "Expected AbstractMutableSet subtype surface to resolve: \(sample41Diagnostics.map(\.message))")

            }

            // === testAbstractMutableMapCanBeUsedAsMapAndMutableMapSupertype ===

            do {

                let sample42Path = paths[42]

                let path = sample42Path

                let sample42Diagnostics = diagnosticsForPath(sample42Path, in: ctx)

                #expect(!(sample42Diagnostics.contains { $0.severity == .error }), "Expected AbstractMutableMap subtype surface to resolve: \(sample42Diagnostics.map(\.message))")

            }

            // === testMutableListIteratorSurfaceIsRegistered ===

            do {

                let sample43Path = paths[43]

                let path = sample43Path

                let sample43Diagnostics = diagnosticsForPath(sample43Path, in: ctx)

                let collectionsPkg = ["kotlin", "collections"].map { interner.intern($0) }
                let listIteratorSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("ListIterator")]))
                let mutableIteratorSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("MutableIterator")]))

                let mutableListIteratorFQName = collectionsPkg + [interner.intern("MutableListIterator")]
                let mutableListIteratorSymbol = try #require(sema.symbols.lookup(fqName: mutableListIteratorFQName))
                let mutableListIteratorInfo = try #require(sema.symbols.symbol(mutableListIteratorSymbol))
                #expect(mutableListIteratorInfo.kind == .interface)
                #expect(mutableListIteratorInfo.flags.contains(.synthetic))
                #expect(sema.types.nominalTypeParameterVariances(for: mutableListIteratorSymbol) == [.invariant])

                let directSupertypes = sema.symbols.directSupertypes(for: mutableListIteratorSymbol)
                #expect(directSupertypes.contains(listIteratorSymbol))
                #expect(directSupertypes.contains(mutableIteratorSymbol))
                #expect(sema.symbols.supertypeTypeArgs(for: mutableListIteratorSymbol, supertype: listIteratorSymbol).count == 1)
                #expect(sema.symbols.supertypeTypeArgs(for: mutableListIteratorSymbol, supertype: mutableIteratorSymbol).count == 1)

                for memberName in ["add", "set"] {
                    let memberSymbol = try #require(sema.symbols.lookup(fqName: mutableListIteratorFQName + [interner.intern(memberName)]))
                    let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
                    #expect(signature.parameterTypes.count == 1)
                    #expect(signature.returnType == sema.types.unitType)
                }
                let removeSymbol = try #require(sema.symbols.lookup(fqName: mutableListIteratorFQName + [interner.intern("remove")]))
                let removeSignature = try #require(sema.symbols.functionSignature(for: removeSymbol))
                #expect(removeSignature.parameterTypes.isEmpty)
                #expect(removeSignature.returnType == sema.types.unitType)

                let mutableListSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("MutableList")]))
                let listIteratorMember = try #require(sema.symbols.lookup(
                        fqName: collectionsPkg + [interner.intern("MutableList"), interner.intern("listIterator")]
                    ))
                #expect(sema.symbols.parentSymbol(for: listIteratorMember) == mutableListSymbol)
                let listIteratorSignature = try #require(sema.symbols.functionSignature(for: listIteratorMember))
                guard case let .classType(returnType) = sema.types.kind(of: listIteratorSignature.returnType) else {
                    Issue.record("MutableList.listIterator should return MutableListIterator<E>")
                    return
                }
                #expect(returnType.classSymbol == mutableListIteratorSymbol)

            }

            // === testMutableIterableSurfaceIsRegistered ===

            do {

                let sample44Path = paths[44]

                let path = sample44Path

                let sample44Diagnostics = diagnosticsForPath(sample44Path, in: ctx)

                let collectionsPkg = ["kotlin", "collections"].map { interner.intern($0) }
                let iterableSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("Iterable")]))
                let iteratorSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("Iterator")]))
                let mutableIteratorSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("MutableIterator")]))
                #expect(sema.types.nominalTypeParameterVariances(for: mutableIteratorSymbol) == [.out])
                #expect(sema.symbols.directSupertypes(for: mutableIteratorSymbol).contains(iteratorSymbol))
                #expect(sema.symbols.supertypeTypeArgs(for: mutableIteratorSymbol, supertype: iteratorSymbol).count == 1)
                let removeSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern("MutableIterator"), interner.intern("remove")]))
                let removeSignature = try #require(sema.symbols.functionSignature(for: removeSymbol))
                #expect(removeSignature.parameterTypes.isEmpty)
                #expect(removeSignature.returnType == sema.types.unitType)

                let mutableIterableFQName = collectionsPkg + [interner.intern("MutableIterable")]
                let mutableIterableSymbol = try #require(sema.symbols.lookup(fqName: mutableIterableFQName))
                let mutableIterableInfo = try #require(sema.symbols.symbol(mutableIterableSymbol))
                #expect(mutableIterableInfo.kind == .interface)
                #expect(mutableIterableInfo.flags.contains(.synthetic))
                #expect(sema.types.nominalTypeParameterVariances(for: mutableIterableSymbol) == [.out])
                #expect(sema.symbols.directSupertypes(for: mutableIterableSymbol).contains(iterableSymbol))
                #expect(sema.types.directNominalSupertypes(for: mutableIterableSymbol).contains(iterableSymbol))
                #expect(sema.symbols.supertypeTypeArgs(for: mutableIterableSymbol, supertype: iterableSymbol).count == 1)

                let iteratorMember = try #require(sema.symbols.lookup(fqName: mutableIterableFQName + [interner.intern("iterator")]))
                #expect(try #require(sema.symbols.symbol(iteratorMember)).flags.contains(.operatorFunction))
                let iteratorSignature = try #require(sema.symbols.functionSignature(for: iteratorMember))
                #expect(iteratorSignature.parameterTypes.isEmpty)
                guard case let .classType(iteratorReturnType) = sema.types.kind(of: iteratorSignature.returnType) else {
                    Issue.record("MutableIterable.iterator should return MutableIterator<T>")
                    return
                }
                #expect(iteratorReturnType.classSymbol == mutableIteratorSymbol)

                for collectionName in ["MutableList", "MutableSet"] {
                    let collectionSymbol = try #require(sema.symbols.lookup(fqName: collectionsPkg + [interner.intern(collectionName)]))
                    #expect(sema.symbols.directSupertypes(for: collectionSymbol).contains(mutableIterableSymbol))
                    #expect(sema.types.directNominalSupertypes(for: collectionSymbol).contains(mutableIterableSymbol))
                    #expect(sema.symbols.supertypeTypeArgs(for: collectionSymbol, supertype: mutableIterableSymbol).count == 1)
                }

            }

            // === testMutableListIteratorMembersResolveFromMutableList ===

            do {

                let sample45Path = paths[45]

                let path = sample45Path

                let sample45Diagnostics = diagnosticsForPath(sample45Path, in: ctx)

                #expect(!(sample45Diagnostics.contains { $0.severity == .error }), "Expected MutableListIterator surface to resolve from MutableList: \(sample45Diagnostics.map(\.message))")

            }

            // === testMutableIterableSubtypeResolution ===

            do {

                let sample46Path = paths[46]

                let path = sample46Path

                let sample46Diagnostics = diagnosticsForPath(sample46Path, in: ctx)

                #expect(!(sample46Diagnostics.contains { $0.severity == .error }), "Expected MutableIterable subtype surface to resolve: \(sample46Diagnostics.map(\.message))")

            }

            // === testSetFallbackRejectsListOnlyIndexedLookups ===

            do {

                let sample47Path = paths[47]

                let path = sample47Path

                let sample47Diagnostics = diagnosticsForPath(sample47Path, in: ctx)

                for memberName in ["firstOrNull", "lastOrNull", "getOrElse"] {
                    let callExpr = try #require(firstExprIDInPath(in: ast, path: sample47Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == memberName
                    })
                    #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == nil, "Expected Set.\(memberName) to remain unresolved")
                }

                #expect(!(sample47Diagnostics.isEmpty), "Expected diagnostics for Set indexed lookup fallbacks")

            }

            // === testCollectionFallbackResolvesTrailingLambdaIndexedLookups ===

            do {

                let sample48Path = paths[48]

                let path = sample48Path

                let sample48Diagnostics = diagnosticsForPath(sample48Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0003", in: sample48Diagnostics)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample48Diagnostics)

                let listCall = try #require(firstExprIDInPath(in: ast, path: sample48Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(receiver, callee, _, _, _) = expr,
                          interner.resolve(callee) == "getOrElse",
                          let receiverExpr = ast.arena.expr(receiver),
                          case let .nameRef(receiverName, _) = receiverExpr
                    else { return false }
                    return interner.resolve(receiverName) == "list"
                })
                let listCallee = try #require(sema.bindings.callBinding(for: listCall)?.chosenCallee)
                let listSymbol = try #require(sema.symbols.symbol(listCallee))
                #expect(sema.symbols.externalLinkName(for: listCallee) == nil)
                #expect(!listSymbol.flags.contains(.synthetic))
                #expect(interner.resolve(listSymbol.name) == "getOrElse")

                let mapCall = try #require(firstExprIDInPath(in: ast, path: sample48Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(receiver, callee, _, _, _) = expr,
                          interner.resolve(callee) == "getOrElse",
                          let receiverExpr = ast.arena.expr(receiver),
                          case let .nameRef(receiverName, _) = receiverExpr
                    else { return false }
                    return interner.resolve(receiverName) == "map"
                })
                let mapCallee = try #require(sema.bindings.callBinding(for: mapCall)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: mapCallee) == "kk_map_getOrElse")

                let mutableCall = try #require(firstExprIDInPath(in: ast, path: sample48Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(receiver, callee, _, _, _) = expr,
                          interner.resolve(callee) == "getOrPut",
                          let receiverExpr = ast.arena.expr(receiver),
                          case let .nameRef(receiverName, _) = receiverExpr
                    else { return false }
                    return interner.resolve(receiverName) == "mutableMap"
                })
                let mutableCallee = try #require(sema.bindings.callBinding(for: mutableCall)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: mutableCallee) == "kk_mutable_map_getOrPut")

            }

            // === testMapGetOrElseAssignsLambdaExpectedTypeToLambdaArgument ===

            do {

                let sample49Path = paths[49]

                let path = sample49Path

                let sample49Diagnostics = diagnosticsForPath(sample49Path, in: ctx)

                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample49Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == "getOrElse"
                    })
                #expect(sema.bindings.exprType(for: callExpr) == sema.types.intType, "Expected getOrElse result to be Int")
                #expect(sample49Diagnostics.isEmpty, "Expected map getOrElse fallback to resolve without diagnostics, got: \(sample49Diagnostics)")

            }

            // === testListBinarySearchHasComparableElementUpperBound ===

            do {

                let sample50Path = paths[50]

                let path = sample50Path

                let sample50Diagnostics = diagnosticsForPath(sample50Path, in: ctx)

                let symbolID = try #require(sema.symbols.lookupAll(
                        fqName: [
                            interner.intern("kotlin"),
                            interner.intern("collections"),
                            interner.intern("List"),
                            interner.intern("binarySearch"),
                        ]
                    ).first(where: { sema.symbols.externalLinkName(for: $0) == "kk_list_binarySearch" }))
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.typeParameterUpperBoundsList.count == 1)
                let upperBounds = signature.typeParameterUpperBoundsList[0]
                #expect(upperBounds.count == 1, "Expected Comparable upper bound for binarySearch element type")

                guard case let .classType(boundType) = sema.types.kind(of: upperBounds[0]) else {
                    Issue.record("Expected binarySearch upper bound to be a class type"); return
                }

                #expect(boundType.classSymbol == sema.types.comparableInterfaceSymbol)
                #expect(boundType.args.count == 1)

                guard case let .invariant(argumentType) = boundType.args[0] else {
                    Issue.record("Expected Comparable upper bound to reference invariant element type"); return
                }

                let expectedElementType = sema.types.make(.typeParam(TypeParamType(
                    symbol: signature.typeParameterSymbols[0],
                    nullability: .nonNull
                )))
                #expect(argumentType == expectedElementType)

            }

            // === testListBinarySearchComparatorOverloadHasDefaultedRange ===

            do {

                let sample51Path = paths[51]

                let path = sample51Path

                let sample51Diagnostics = diagnosticsForPath(sample51Path, in: ctx)

                let listSymbol = try #require(sema.symbols.lookup(fqName: [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("List"),
                    ]))
                let symbolID = try #require(sema.symbols.lookupByShortName(interner.intern("binarySearch")).first(where: { candidate in
                        sema.symbols.parentSymbol(for: candidate) == listSymbol
                            && sema.symbols.externalLinkName(for: candidate) == "kk_list_binarySearch_comparator"
                    }))
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes.count == 4)
                #expect(signature.valueParameterSymbols.count == 4)
                #expect(signature.valueParameterHasDefaultValues == [false, false, true, true])
                #expect(signature.typeParameterSymbols.count == 1)
                #expect(signature.classTypeParameterCount == 1)
                #expect(signature.typeParameterUpperBoundsList.isEmpty)

                let parameterNames = signature.valueParameterSymbols.compactMap { paramSymbol in
                    sema.symbols.symbol(paramSymbol)?.name
                }.map { interner.resolve($0) }
                #expect(parameterNames == ["element", "comparator", "fromIndex", "toIndex"])

                #expect(signature.parameterTypes[0] == sema.types.make(.typeParam(TypeParamType(
                    symbol: signature.typeParameterSymbols[0],
                    nullability: .nonNull
                ))))
                #expect(signature.parameterTypes[2] == sema.types.intType)
                #expect(signature.parameterTypes[3] == sema.types.intType)

                if let comparatorSymbol = sema.symbols.lookupByShortName(interner.intern("Comparator")).first,
                   case let .classType(comparatorClassType) = sema.types.kind(of: signature.parameterTypes[1])
                {
                    #expect(comparatorClassType.classSymbol == comparatorSymbol)
                    #expect(comparatorClassType.args.count == 1)
                } else {
                    guard case let .functionType(comparatorFunctionType) = sema.types.kind(of: signature.parameterTypes[1]) else {
                        Issue.record("Expected binarySearch comparator parameter to be Comparator<T> or a comparator function type"); return
                    }
                    #expect(comparatorFunctionType.params.count == 2)
                    #expect(comparatorFunctionType.returnType == sema.types.intType)
                }

            }

            // === testListBinarySearchByUsesComparableKeyAndRuntimeOverloads ===

            do {

                let sample52Path = paths[52]

                let path = sample52Path

                let sample52Diagnostics = diagnosticsForPath(sample52Path, in: ctx)

                let expectedOverloads: [(externalLinkName: String, parameterCount: Int)] = [
                    ("kk_list_binarySearchBy", 2),
                    ("kk_list_binarySearchBy_fromIndex", 3),
                    ("kk_list_binarySearchBy_range", 4),
                ]

                let callExprIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                    let exprID = ExprID(rawValue: Int32(index))
                    guard let expr = ast.arena.expr(exprID),
                          case let .memberCall(_, callee, _, _, _) = expr,
                          interner.resolve(callee) == "binarySearchBy"
                    else {
                        return nil
                    }
                    return exprID
                }
                #expect(callExprIDs.count == expectedOverloads.count, "Expected three binarySearchBy calls")

                for (index, callExprID) in callExprIDs.enumerated() {
                    let chosenCallee = try #require(sema.bindings.callBinding(for: callExprID)?.chosenCallee)
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == expectedOverloads[index].externalLinkName, "Expected binarySearchBy overload \(index) to resolve to \(expectedOverloads[index].externalLinkName)")
                    #expect(sema.bindings.exprType(for: callExprID) == sema.types.intType, "Expected binarySearchBy overload \(index) to return Int")
                }

                let listFQName: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("List"),
                    interner.intern("binarySearchBy"),
                ]

                for overload in expectedOverloads {
                    let symbolID = try #require(sema.symbols.lookupAll(fqName: listFQName).first(where: {
                            sema.symbols.externalLinkName(for: $0) == overload.externalLinkName
                        }))
                    let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                    #expect(signature.returnType == sema.types.intType)
                    #expect(signature.parameterTypes.count == overload.parameterCount)
                    #expect(signature.typeParameterSymbols.count == 2)
                    #expect(signature.typeParameterUpperBoundsList.count == 2)

                    let selectorType = try #require(signature.parameterTypes.last)
                    guard case let .functionType(functionType) = sema.types.kind(of: selectorType) else {
                        Issue.record("Expected selector parameter for \(overload.externalLinkName) to be a function type"); return
                    }
                    #expect(functionType.params.count == 1)

                    let expectedListElementType = sema.types.make(.typeParam(TypeParamType(
                        symbol: signature.typeParameterSymbols[0],
                        nullability: .nonNull
                    )))
                    #expect(functionType.params[0] == expectedListElementType)
                    #expect(functionType.returnType == signature.parameterTypes[0])

                    let keyUpperBounds = signature.typeParameterUpperBoundsList[1]
                    #expect(keyUpperBounds.count == 1, "Expected Comparable upper bound for \(overload.externalLinkName) key type")
                    guard case let .classType(boundType) = sema.types.kind(of: keyUpperBounds[0]) else {
                        Issue.record("Expected \(overload.externalLinkName) upper bound to be a class type"); return
                    }
                    #expect(boundType.classSymbol == sema.types.comparableInterfaceSymbol)
                    #expect(boundType.args.count == 1)

                    guard case let .invariant(argumentType) = boundType.args[0] else {
                        Issue.record("Expected \(overload.externalLinkName) upper bound to reference invariant key type"); return
                    }

                    let expectedKeyType = sema.types.make(.typeParam(TypeParamType(
                        symbol: signature.typeParameterSymbols[1],
                        nullability: .nonNull
                    )))
                    #expect(argumentType == expectedKeyType)
                    #expect(signature.parameterTypes[0] == sema.types.makeNullable(expectedKeyType))

                    if overload.parameterCount >= 3 {
                        #expect(signature.parameterTypes[1] == sema.types.intType)
                    }
                    if overload.parameterCount == 4 {
                        #expect(signature.parameterTypes[2] == sema.types.intType)
                    }
                }

            }

            // === testListToTypeArrayUsesTypedArrayRuntimeExternalLink ===

            do {

                let sample53Path = paths[53]

                let path = sample53Path

                let sample53Diagnostics = diagnosticsForPath(sample53Path, in: ctx)

                #expect(sample53Diagnostics.isEmpty, "Unexpected diagnostics: \(sample53Diagnostics.map(\.message))")
                let callExpr = try #require(firstExprIDInPath(in: ast, path: sample53Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "toTypedArray"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_list_toTypedArray")
                let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                guard case let .classType(classType) = sema.types.kind(of: signature.returnType),
                      let symbol = sema.symbols.symbol(classType.classSymbol)
                else {
                    Issue.record("Expected toTypedArray to return Array"); return
                }
                #expect(interner.resolve(symbol.name) == "Array")

            }

            // === testIterableLocalVariableFromNonFactoryFunctionResolvesFilterAndCount ===

            do {

                let sample54Path = paths[54]

                let path = sample54Path

                let sample54Diagnostics = diagnosticsForPath(sample54Path, in: ctx)

                // Regression test: assigning the result of an ordinary (non collection-factory)
                // function call to an explicitly `Iterable<T>`-typed local used to leave that
                // local's receiver classification without isCollectionExpr/isCollectionType/
                // isSequenceReceiver, so tryCollectionMemberFallback's guard rejected members
                // like filter/count even though the static receiver type is nominally Iterable.
                    #expect(!(sample54Diagnostics.contains { $0.severity == .error }), "Expected Iterable<T> local from a non-factory function call to resolve filter/count cleanly, got: \(sample54Diagnostics.map { "\($0.code): \($0.message)" })")

                    let filterExpr = try #require(firstExprIDInPath(in: ast, path: sample54Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == "filter"
                    })
                    #expect(sema.bindings.callBinding(for: filterExpr)?.chosenCallee != nil, "Expected filter call on the Iterable-typed local to bind to a callee")

                    let countExpr = try #require(firstExprIDInPath(in: ast, path: sample54Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                        return interner.resolve(callee) == "count" && args.isEmpty
                    })
                    #expect(sema.bindings.exprType(for: countExpr) == sema.types.intType)

            }

            // === testIterableParameterFromNonListLiteralArgumentResolvesFilterAndCount ===

            do {

                let sample55Path = paths[55]

                let path = sample55Path

                let sample55Diagnostics = diagnosticsForPath(sample55Path, in: ctx)

                // Companion regression coverage: the same static-type gap also affected
                // Iterable<T>-typed function parameters (not just locals), since parameters
                // never carry the isCollectionExpr propagation mark either.
                    #expect(!(sample55Diagnostics.contains { $0.severity == .error }), "Expected Iterable<T> parameter to resolve filter/count cleanly, got: \(sample55Diagnostics.map { "\($0.code): \($0.message)" })")

            }

        }
    }

}

struct SyntheticMemberCallCase {
    let source: String
    let memberName: String
    let expectedExternalLink: String
    let expectedTypeShape: SyntheticMemberTypeShape?
}

enum SyntheticMemberTypeShape {
    case classNamed(String)
}

func assertSyntheticMemberCall(
    _ testCase: SyntheticMemberCallCase,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    try withTemporaryFile(contents: testCase.source) { path in
        let ctx = makeCompilationContext(inputs: [path])
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected \(testCase.memberName) to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        // Use lastExprID rather than firstExprID: bundled stdlib sources (injected
        // before the fixture's own source) may contain unrelated calls to the same
        // member name (e.g. Sequence aggregate HOFs calling `this.toList()`
        // internally), which would otherwise shadow the fixture's own call site.
        let callExpr = try #require(lastExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == testCase.memberName
        })
        let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
        #expect(sema.symbols.externalLinkName(for: chosenCallee) == testCase.expectedExternalLink, "Expected \(testCase.memberName) to resolve to \(testCase.expectedExternalLink)")

        if let expectedTypeShape = testCase.expectedTypeShape {
            let resultType = try #require(sema.bindings.exprType(for: callExpr))
            try assertSyntheticMemberType(
                resultType,
                matches: expectedTypeShape,
                sema: sema,
                interner: ctx.interner,
                memberName: testCase.memberName,
                file: file,
                line: line
            )
        }
    }
}

func assertSyntheticMemberType(
    _ type: TypeID,
    matches expectedTypeShape: SyntheticMemberTypeShape,
    sema: SemaModule,
    interner: StringInterner,
    memberName: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    switch expectedTypeShape {
    case let .classNamed(expectedName):
        guard case let .classType(classType) = sema.types.kind(of: type),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            Issue.record("Expected \(memberName) to return \(expectedName)"); return
        }
        #expect(interner.resolve(symbol.name) == expectedName)
    }
}

func projectedType(
    _ arg: TypeArg,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> TypeID {
    switch arg {
    case let .invariant(type), let .out(type), let .in(type):
        return type
    case .star:
        return try #require(nil as TypeID?)
    }
}

func assertListType(
    _ type: TypeID,
    elementType expectedElementType: TypeID,
    sema: SemaModule,
    interner: StringInterner,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard case let .classType(listType) = sema.types.kind(of: type) else {
        Issue.record("Expected List type"); return
    }
    #expect(try interner.resolve(#require(sema.symbols.symbol(listType.classSymbol)?.name)) == "List")
    #expect(listType.args.count == 1)
    let elementType = try projectedType(try #require(listType.args.first), file: file, line: line)
    #expect(elementType == expectedElementType)
}
#endif
