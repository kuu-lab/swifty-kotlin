@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionMutationAndAdvancedTests {
    @Test
    func testCodegenCollectionConstructorsCopySourceElements() throws {
        let source = """
        fun main() {
            val source: Collection<Int> = listOf(1, 2)
            val copiedList = ArrayList(source)
            copiedList.add(3)
            println(source.size)
            println(copiedList.size)
            println(copiedList.contains(3))
            println(source.contains(3))

            val duplicated: Collection<Int> = listOf(1, 2, 2)
            val hashCopy = HashSet(duplicated)
            hashCopy.add(4)
            println(hashCopy.size)
            println(hashCopy.contains(1))
            println(duplicated.size)

            val sourceSet: Set<Int> = setOf(2, 1)
            val linkedCopy = LinkedHashSet(sourceSet)
            linkedCopy.add(5)
            println(linkedCopy.contains(2))
            println(sourceSet.contains(5))
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionConstructorCopyRuntime", expected: "2\n3\ntrue\nfalse\n3\ntrue\n3\ntrue\nfalse\n")
    }

    @Test
    func testCodegenCollectionCopiesProduceIndependentMutableAndSetViews() throws {
        let source = """
        fun main() {
            val sourceList = listOf(1, 2, 2)
            val copiedList = sourceList.toMutableList()
            copiedList.add(3)
            println(sourceList)
            println(copiedList)

            val copiedSet = sourceList.toSet()
            println(copiedSet)
            println(copiedSet.contains(2))

            val sourceMap = mapOf("a" to 1)
            val copiedMap = sourceMap.toMutableMap()
            copiedMap["b"] = 2
            println(sourceMap)
            println(copiedMap)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionCopiesRuntime", expected: "[1, 2, 2]\n[1, 2, 2, 3]\n[1, 2]\ntrue\n{a=1}\n{a=1, b=2}\n")
    }

    @Test
    func testCodegenListToMapKeepsLastValueForDuplicateKeys() throws {
        let source = """
        fun main() {
            val map = listOf(1 to "one", 2 to "two", 1 to "uno").toMap()
            println(map.size)
            println(map[1])
            println(map[2])
            println(map.containsKey(3))
        }
        """

        try assertKotlinOutput(source, moduleName: "ListToMapRuntime", expected: "2\nuno\ntwo\nfalse\n")
    }

    @Test
    func testCodegenListUnionUsesRuntimeSetOperation() throws {
        let source = """
        fun main() {
            val values: List<Int> = listOf(1, 2, 2, 3)
            val other: List<Int> = listOf(3, 4, 2, 5)
            val unioned = values.union(other)
            println(unioned.size)
            println(unioned.contains(1))
            println(unioned.contains(4))
            println(unioned.contains(9))
        }
        """

        try assertKotlinOutput(source, moduleName: "ListUnionRuntime", expected: "5\ntrue\ntrue\nfalse\n")
    }

    @Test
    func testCodegenCollectionAndIterableToMutableListReturnIndependentCopies() throws {
        let source = """
        fun main() {
            val sourceCollection: Collection<Int> = listOf(1, 2, 3)
            val collectionCopy = sourceCollection.toMutableList()
            collectionCopy.add(4)
            println(sourceCollection)
            println(collectionCopy)

            val sourceIterable: Iterable<Int> = setOf(3, 1, 2)
            val iterableCopy = sourceIterable.toMutableList()
            iterableCopy.add(9)
            println(sourceIterable)
            println(iterableCopy)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionIterableToMutableListRuntime", expected: "[1, 2, 3]\n[1, 2, 3, 4]\n[3, 1, 2]\n[3, 1, 2, 9]\n")
    }

    @Test
    func testCodegenCollectionToListCopiesListAndSetReceivers() throws {
        let source = """
        fun main() {
            val sourceList = listOf(1, 2, 3)
            val copiedList = sourceList.toList()
            println(copiedList)

            val sourceSet = setOf(3, 1, 3, 2)
            val copiedSetList = sourceSet.toList()
            println(copiedSetList)
            println(copiedSetList.contains(2))
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionToListRuntime", expected: "[1, 2, 3]\n[3, 1, 2]\ntrue\n")
    }

    @Test
    func testCodegenCollectionToTypedArrayCopiesListAndSetReceivers() throws {
        let source = """
        fun main() {
            val sourceCollection: Collection<Int> = listOf(1, 2, 3)
            val copiedArray = sourceCollection.toTypedArray()
            println(copiedArray.toList())
            copiedArray[0] = 9
            println(sourceCollection)
            println(copiedArray.toList())

            val sourceSet: Collection<Int> = setOf(3, 1, 3, 2)
            val setArray = sourceSet.toTypedArray()
            println(setArray.toList())
            println(setArray.size)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionToTypedArrayRuntime", expected: "[1, 2, 3]\n[1, 2, 3]\n[9, 2, 3]\n[3, 1, 2]\n3\n")
    }

    @Test
    func testCodegenIterableToMutableSetDeduplicatesAndReturnsIndependentCopy() throws {
        let source = """
        fun main() {
            val sourceIterable: Iterable<Int> = listOf(3, 1, 2, 1)
            val mutableSet = sourceIterable.toMutableSet()
            mutableSet.add(9)
            println(sourceIterable)
            println(mutableSet)
            println(mutableSet.contains(1))
        }
        """

        try assertKotlinOutput(source, moduleName: "IterableToMutableSetRuntime", expected: "[3, 1, 2, 1]\n[3, 1, 2, 9]\ntrue\n")
    }

    @Test
    func testCodegenListJoinToStringUsesRuntimeDefaultsAndNamedArguments() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            println(list.joinToString())
            println(list.joinToString(" | "))
            println(list.joinToString(prefix = "<", postfix = ">"))
            println(list.joinToString(separator = ":", prefix = "[", postfix = "]"))
        }
        """

        try assertKotlinOutput(source, moduleName: "ListJoinToStringRuntime", expected: "1, 2, 3\n1 | 2 | 3\n<1, 2, 3>\n[1:2:3]\n")
    }

    @Test
    func testCodegenSequenceJoinToStringUsesRuntimeDefaultsAndNamedArguments() throws {
        let source = """
        fun main() {
            println(sequenceOf(1, 2, 3).joinToString(", "))
            println(sequenceOf("a", "b", "c").joinToString("-"))
            println(listOf<String>().asSequence().joinToString(prefix = "<", postfix = ">"))
            println(sequenceOf(1, 2, 3).joinToString(separator = ":", prefix = "[", postfix = "]"))
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceJoinToStringRuntime", expected: "1, 2, 3\na-b-c\n<>\n[1:2:3]\n")
    }

    @Test
    func testCodegenListMapNotNullAndFilterNotNullUseRuntimeHOFs() throws {
        let source = """
        fun main() {
            val values = listOf(1, 0, 2)
            val numbers = values.mapNotNull { it }
            println(numbers)

            val nullable = listOf("a", null, "b", null)
            println(nullable.filterNotNull())
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMapNotNullAndFilterNotNullRuntime", expected: "[1, 0, 2]\n[a, b]\n")
    }

    @Test
    func testCodegenListMaxByReturnsSelectedElementAndThrowsOnEmpty() throws {
        let source = """
        fun main() {
            val values = listOf(3, 1, 4, 2)
            println(values.maxBy { -it })
            try {
                emptyList<Int>().maxBy { -it }
                println("missing")
            } catch (e: NoSuchElementException) {
                println("empty")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMaxByRuntime", expected: "1\nempty\n")
    }

    @Test
    func testCodegenListFilterNotUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3, 4)
            println(values.filterNot { it % 2 == 0 })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListFilterNotRuntime", expected: "[1, 3]\n")
    }

    @Test
    func testCodegenListMaxByOrNullReturnsSelectedElementOrNull() throws {
        let source = """
        fun main() {
            val values = listOf(3, 1, 4, 2)
            println(values.maxByOrNull { -it })
            println(emptyList<Int>().maxByOrNull { -it })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMaxByOrNullRuntime", expected: "1\nnull\n")
    }

    @Test
    func testCodegenIterableFirstNotNullOfOrNullReturnsFirstValueOrNull() throws {
        let source = """
        fun main() {
            val result: String? = listOf(1, 2, 3).firstNotNullOfOrNull { if (it > 1) "hit" else null }
            println(result)
            val missing: String? = listOf(1, 3, 5).firstNotNullOfOrNull { if (it % 2 == 0) "even" else null }
            println(missing)
        }
        """

        try assertKotlinOutput(source, moduleName: "IterableFirstNotNullOfOrNullRuntime", expected: "hit\nnull\n")
    }

    @Test
    func testCodegenListZipAndUnzipUseRuntimeHOFs() throws {
        let source = """
        fun main() {
            val left = listOf(1, 2, 3)
            val right = listOf("a", "b")
            val zipped = left.zip(right)
            println(zipped)
            println(zipped.unzip())
        }
        """

        try assertKotlinOutput(source, moduleName: "ListZipAndUnzipRuntime", expected: "[(1, a), (2, b)]\n([1, 2], [a, b])\n")
    }

    @Test
    func testCodegenListTransformsUseRuntimeHelpers() throws {
        let source = """
        fun main() {
            val list = listOf(3, 1, 2, 1)
            println(list.take(3))
            println(list.drop(2))
            println(list.reversed())
            println(list.sorted())
            println(list.distinct())
            println(list.takeWhile { it > 2 })
            println(list.dropLastWhile { it == 1 })
            renderPrefix(list)
            renderSuffix(list)
            try {
                println(list.take(-1))
                println("missing-take")
            } catch (e: IllegalArgumentException) {
                println("negative-take")
            }
            try {
                println(list.drop(-1))
                println("missing-drop")
            } catch (e: IllegalArgumentException) {
                println("negative-drop")
            }
            render(list)
        }

        fun render(values: List<Int>) {
            try {
                println(values.take(-1))
                println("missing-param-take")
            } catch (e: IllegalArgumentException) {
                println("negative-param-take")
            }
        }

        fun renderPrefix(values: List<Int>) {
            println(values.takeWhile { it > 2 })
            try {
                println(values.takeWhile {
                    if (it == 3) {
                        throw IllegalArgumentException("prefix")
                    }
                    true
                })
                println("missing-prefix")
            } catch (e: IllegalArgumentException) {
                println("negative-prefix")
            }
        }

        fun renderSuffix(values: List<Int>) {
            println(values.dropLastWhile { it == 1 })
            try {
                println(values.dropLastWhile {
                    if (it == 1) {
                        throw IllegalArgumentException("suffix")
                    }
                    true
                })
                println("missing-suffix")
            } catch (e: IllegalArgumentException) {
                println("thrown-suffix")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ListTransformsRuntime", expected: "[3, 1, 2]\n[2, 1]\n[1, 2, 1, 3]\n[1, 1, 2, 3]\n[3, 1, 2]\n[3]\n[3, 1, 2]\n[3]\nnegative-prefix\n[3, 1, 2]\nthrown-suffix\nnegative-take\nnegative-drop\nnegative-param-take\n")
    }

    @Test
    func testCodegenListElementAtUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val list = listOf(10, 20, 30)
            println(list.elementAt(1))
        }
        """

        try assertKotlinOutput(source, moduleName: "ListElementAtRuntime", expected: "20\n")
    }

    @Test
    func testCodegenMutableListFillUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val list = mutableListOf(1, 2, 3)
            list.fill(9)
            println(list)
        }
        """

        try assertKotlinOutput(source, moduleName: "MutableListFillRuntime", expected: "[9, 9, 9]\n")
    }
    @Test
    func testCodegenListElementAtOrNullUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val list = listOf(10, 20, 30)
            println(list.elementAtOrNull(1) ?: -1)
            println(list.elementAtOrNull(5) ?: -1)
        }
        """

        try assertKotlinOutput(source, moduleName: "ListElementAtOrNullRuntime", expected: "20\n-1\n")
    }

    @Test
    func testCodegenListAggregateHelpersUseRuntimeHelpers() throws {
        let source = """
        fun main() {
            val list = listOf(3, 1, 2)
            println(list.flatMap { listOf(it, it * 10) })
            println(list.get(0))
            println(list.sumOf { it * 2 })
            println(list.minBy { it % 3 })
            println(list.maxOrNull())
            println(list.minOrNull())
            println(list.minOfOrNull { it * 10 })
            println(list.minByOrNull { it % 3 })
            println(list.fold(0) { acc, value -> acc * 10 + value })
            println(list.foldRight(0) { value, acc -> value * 10 + acc })
            println(list.foldIndexed(0) { index, acc, value -> acc + index * value })
            println(setOf(3, 1, 2).foldIndexed(0) { index, acc, value -> acc + index * value })
            println(list.foldRightIndexed(0) { index, value, acc -> index + value + acc })
            println(setOf(3, 1, 2).fold(0) { acc, value -> acc * 10 + value })
            println(list.find { it > 1 })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ListAggregateRuntime", emit: .llvmIR)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            // flatMap and the fold/*Indexed family are now bundled Kotlin source
            // functions, so they are inlined/expanded into the core List access
            // helpers (__kk_list_get / __kk_list_size) and mutable add.  The
            // aggregate helpers that still lack source implementations continue
            // to call their runtime counterparts.
            #expect(callees.contains("__kk_list_get"), "callees: \(callees.sorted())")
            #expect(callees.contains("__kk_list_size") || callees.contains("__kk_collection_size"), "callees: \(callees.sorted())")
            #expect(callees.contains("__kk_collection_size"), "callees: \(callees.sorted())")
            #expect(callees.contains("__kk_mutable_list_add"), "callees: \(callees.sorted())")
            #expect(callees.contains("kk_list_sumOf") || callees.contains("sumOf"))
            #expect(callees.contains("kk_list_minBy"))
            #expect(callees.contains("kk_list_maxOrNull"))
            #expect(callees.contains("kk_list_minOrNull"))
            #expect(callees.contains("kk_list_minOfOrNull"))
            #expect(callees.contains("kk_list_minByOrNull"))
            // The old runtime entry points for source-backed HOFs must not appear
            // after lowering; their bodies have been expanded inline.
            #expect(!(callees.contains("kk_list_flatMap")), "callees: \(callees.sorted())")
            #expect(!(callees.contains("kk_list_find")), "callees: \(callees.sorted())")
            #expect(!(callees.contains("kk_list_fold")), "callees: \(callees.sorted())")
            #expect(!(callees.contains("kk_list_foldIndexed")), "callees: \(callees.sorted())")
            #expect(!(callees.contains("kk_list_foldRightIndexed")), "callees: \(callees.sorted())")
        }
    }

    @Test
    func testCodegenListAverageUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val list = listOf(2, 4, 6)
            println(list.average())
        }
        """

        try assertKotlinOutput(source, moduleName: "ListAverageRuntime", expected: "4.0\n")
    }

    @Test
    func testCodegenListMinOrNullReturnsSmallestElementAndNullOnEmpty() throws {
        let source = """
        fun main() {
            println(listOf(5, 2, 3).minOrNull())
            println(emptyList<Int>().minOrNull() == null)
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMinOrNullRuntime", expected: "2\ntrue\n")
    }

    @Test
    func testCodegenListMinByOrNullReturnsSmallestSelectedElementAndNullOnEmpty() throws {
        let source = """
        fun main() {
            val values = listOf(5, 2, 3)
            println(values.minByOrNull { it % 3 })
            val empty = emptyList<Int>()
            println(empty.minByOrNull { it % 3 } == null)
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMinByOrNullRuntime", expected: "3\ntrue\n")
    }

    @Test
    func testCodegenListMinByReturnsSmallestSelectedElementAndThrowsOnEmpty() throws {
        let source = """
        fun main() {
            val values = listOf(5, 2, 3)
            println(values.minBy { it % 3 })
            try {
                emptyList<Int>().minBy { it }
                println("missing")
            } catch (e: NoSuchElementException) {
                println("empty")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMinByRuntime", expected: "3\nempty\n")
    }

    @Test
    func testCodegenListMinReturnsSmallestElementAndThrowsOnEmpty() throws {
        let source = """
        fun main() {
            val values = listOf(3, 1, 4, 2)
            println(values.min())
            try {
                emptyList<Int>().min()
                println("missing")
            } catch (e: NoSuchElementException) {
                println("empty")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMinRuntime", expected: "1\nempty\n")
    }

    @Test
    func testCodegenListMinOfWithOrNullReturnsComparatorSelectedValueAndNullOnEmpty() throws {
        let source = """
        fun main() {
            println(listOf(5, 2, 3).minOfOrNull { it * 10 })
            println(emptyList<Int>().minOfOrNull { it * 10 } == null)
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMinOfOrNullRuntime", expected: "20\ntrue\n")
    }

    @Test
    func testCodegenMapFilterValuesReturnsFilteredEntries() throws {
        let source = """
        fun main() {
            val values = mapOf("a" to 1, "b" to 2, "c" to 3)
            println(values.filterValues { it % 2 == 0 })
        }
        """

        try assertKotlinOutput(source, moduleName: "MapFilterValuesRuntime", expected: "{b=2}\n")
    }

    @Test
    func testCodegenMapHigherOrderHelpersUseRuntimeHelpers() throws {
        let source = """
        fun main() {
            val values = mapOf("a" to 1, "b" to 2)
            values.forEach {
                println("${it.key}=${it.value}")
            }
            println(values.map { it.key + ":" + (it.value * 10) })
            println(values.filter { it.value % 2 == 0 })
            println(values.mapValues { it.value * 10 })
            println(values.mapKeys { it.key + "!" })
            println(values.filterKeys { it == "b" })
            println(values.toList())
            println(values.map { it.toPair().first + ":" + (it.toPair().second + 1) })
        }
        """

        try assertKotlinOutput(source, moduleName: "MapHigherOrderRuntime", expected: "a=1\nb=2\n[a:10, b:20]\n{b=2}\n{a=10, b=20}\n{a!=1, b!=2}\n{b=2}\n[(a, 1), (b, 2)]\n[a:2, b:3]\n")
    }

    @Test
    func testCodegenMapPropertyAccessesUseRuntimeHelpers() throws {
        let source = """
        fun main() {
            val values = mapOf("a" to 1, "b" to 2)
            println(values.keys)
            println(values.values)
            println(values.entries)
        }
        """

        try assertKotlinOutput(source, moduleName: "MapPropertyRuntime", expected: "[a, b]\n[1, 2]\n[a=1, b=2]\n")
    }

    @Test
    func testCodegenListAssociateHelpersUseRuntimeMapBuilders() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.associate { (it % 2) to (it * 10) })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListAssociateRuntime", expected: "{1=30, 0=20}\n")
    }

    @Test
    func testCodegenListAssociateWithUsesRuntimeMapBuilder() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.associateWith { it * 10 })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListAssociateWithRuntime", expected: "{1=10, 2=20, 3=30}\n")
    }

    @Test
    func testCodegenListAssociateByUsesRuntimeMapBuilder() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.associateBy { it % 2 })
            println(values.associateBy({ it % 2 }, { it * 10 }))
        }
        """

        try assertKotlinOutput(source, moduleName: "ListAssociateByRuntime", expected: "{1=3, 0=2}\n{1=30, 0=20}\n")
    }

    @Test
    func testCodegenMutableMapCastsToMap() throws {
        let source = """
        fun main() {
            val m = mutableMapOf<Int, String>()
            m[1] = "one"
            val n: Map<Int, String> = m as Map<Int, String>
            println(n[1])
        }
        """

        try assertKotlinOutput(source, moduleName: "MutableMapCastToMapRuntime", expected: "one\n")
    }

    @Test
    func testCodegenListGroupByUsesRuntimeMapBuilder() throws {
        let source = """
        fun main() {
            val values = listOf("a", "bb", "cc", "ddd")
            println(values.groupBy { it.length })
            println(values.groupBy({ it.length }, { it.uppercase() }))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListGroupByRuntime",
            expected: "{1=[a], 2=[bb, cc], 3=[ddd]}\n{1=[A], 2=[BB, CC], 3=[DDD]}\n"
        )
    }

    @Test
    func testCodegenListPartitionOnEachAndWithIndex() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3, 4)
            println(values.partition { it % 2 == 0 })
            val indexed = values.withIndex()
            for (iv in indexed) {
                println(iv.index)
                println(iv.value)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListPartitionOnEachWithIndexRuntime",
            expected: "([2, 4], [1, 3])\n0\n1\n1\n2\n2\n3\n3\n4\n"
        )
    }

    @Test
    func testCodegenListIndexedHelpersUseRuntimeHOFs() throws {
        let source = """
        fun main() {
            val values = listOf("a", "bb")
            values.forEachIndexed { index, value ->
                println(index * 10 + value.length)
            }
            println(values.mapIndexed { index, value -> index + value.length })
            println(listOf(10, 20, 30, 40).filterIndexed { index, value -> index + value > 21 })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListIndexedHelpersRuntime", expected: "1\n12\n[1, 3]\n[30, 40]\n")
    }

    @Test
    func testCodegenListFilterIsInstanceUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val values: List<Any> = listOf(1, "two", 3)
            println(values.filterIsInstance<Int>())
        }
        """

        try assertKotlinOutput(source, moduleName: "ListFilterIsInstanceRuntime", expected: "[1, 3]\n")
    }

    @Test
    func testCodegenStringContainsEmptyNeedleReturnsTrue() throws {
        let source = """
        fun main() {
            println("hello world".contains(""))
        }
        """

        try assertKotlinOutput(source, moduleName: "StringContainsEmptyNeedle", expected: "true\n")
    }

    @Test
    func testCodegenRepeatDelayCancellationReachesLocalCatch() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.channels.*
        import kotlin.coroutines.cancellation.cancel

        fun main() = runBlocking {
            val started = Channel<Int>()
            val job = launch {
                try {
                    started.send(1)
                    repeat(1000) {
                        delay(10)
                    }
                } catch (e: CancellationException) {
                    println("cancelled")
                }
            }
            val jobContext = job + Dispatchers.Default
            started.receive()
            jobContext.cancel()
            job.join()
            println("done")
        }
        """

        try assertKotlinOutput(source, moduleName: "RepeatDelayCancellation", expected: "cancelled\ndone\n")
    }

    @Test
    func testCodegenCoroutineCancellationExtensionImportWorks() throws {
        let source = """
        import kotlin.coroutines.cancellation.cancel
        import kotlinx.coroutines.*
        import kotlinx.coroutines.channels.*

        fun main() = runBlocking {
            val started = Channel<Int>()
            val job = launch {
                try {
                    started.send(1)
                    repeat(1000) {
                        delay(10)
                    }
                } catch (e: CancellationException) {
                    println("cancelled")
                }
            }
            started.receive()
            job.cancel()
            job.join()
            println("done")
        }
        """

        try assertKotlinOutput(source, moduleName: "CoroutineCancellationExtensionImportWorks", expected: "cancelled\ndone\n")
    }

    @Test
    func testCodegenSuspendCoroutineReturnsResumedValue() throws {
        let source = """
        import kotlin.coroutines.*

        suspend fun probe(): Int {
            return suspendCoroutine<Int> { cont: Continuation<Int> ->
                cont.resume(42)
            }
        }

        fun main() {
            println(runBlocking(probe))
        }
        """

        try assertKotlinOutput(source, moduleName: "SuspendCoroutineRuntime", expected: "42\n")
    }

    @Test
    func testCodegenSuspendCoroutinePropagatesResumedException() throws {
        let source = """
        import kotlin.coroutines.*

        suspend fun probe(): Int {
            return suspendCoroutine<Int> { cont: Continuation<Int> ->
                cont.resumeWithException(IllegalStateException("boom"))
            }
        }

        fun main() {
            try {
                println(runBlocking(probe))
            } catch (e: Throwable) {
                println(e.message ?: "missing")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "SuspendCoroutineRuntimeException", expected: "boom\n")
    }

    @Test
    func testCodegenEmitsObjectWhenLlvmBindingsAreRequired() throws {
        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "LLVMRequired",
                inputs: [path],
                outputPath: outputBase,
                emit: .object,
                target: defaultTargetTriple()
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            let objectPath = try #require(ctx.generatedObjectPath)
            #expect(FileManager.default.fileExists(atPath: objectPath))
            #expect(!(ctx.diagnostics.diagnostics.contains { $0.severity == .error }))
        }
    }

    @Test
    func testLLVMBackendNativeFailureReportsEmissionError() throws {
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 2500),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )
        let functionID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [functionID])],
            arena: arena
        )

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: diagnostics
        )

        let missingObjectPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing")
            .appendingPathComponent("out.o")
            .path

        #expect(throws: (any Error).self) {
            try backend.emitObject(
                module: module,
                outputObjectPath: missingObjectPath,
                interner: interner
            )
        }
        #expect(diagnostics.diagnostics.contains { $0.code == "KSWIFTK-BACKEND-1006" })
        #expect(!(diagnostics.diagnostics.contains { $0.code == "KSWIFTK-BACKEND-1005" }))
    }

    @Test
    func testCodegenListMaxWithReturnsLargestElementAndThrowsOnEmpty() throws {
        let source = """
        fun main() {
            val values = listOf(3, 1, 4, 2)
            println(values.maxWith(naturalOrder<Int>()))
            try {
                emptyList<Int>().maxWith(naturalOrder<Int>())
                println("missing")
            } catch (e: NoSuchElementException) {
                println("empty")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMaxWithRuntime", expected: "4\nempty\n")
    }

    @Test
    func testCodegenListToTypeArrayUsesTypedArrayRuntime() throws {
        let source = """
        fun main() {
            val array = listOf(3, 1, 2).toTypedArray()
            println(array.size)
            println(array[0])
            println(array[2])
            println(array.toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "ListToTypeArrayRuntime", expected: "3\n3\n2\n[3, 1, 2]\n")
    }
}

private func runCodegenPipeline(
    inputPath: String,
    moduleName: String,
    emit: EmitMode,
    outputPath: String,
    irFlags: [String] = []
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple(),
        irFlags: irFlags
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    if emit == .kirDump {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for dump.")
        }
        let path = outputPath + ".kir"
        let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    } else {
        try CodegenPhase().run(ctx)
    }
    return ctx
}

private func assertKotlinOutput(
    _ source: String,
    moduleName: String,
    expected: String
) throws {
    try withTemporaryFile(contents: source) { path in
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let ctx = try runCodegenPipeline(
            inputPath: path,
            moduleName: moduleName,
            emit: .executable,
            outputPath: outputBase
        )
        try LinkPhase().run(ctx)
        let result = try CommandRunner.run(executable: outputBase, arguments: [])
        let normalizedStdout = result.stdout
            .replacingOccurrences(of: "\r\n", with: "\n")
        #expect(normalizedStdout == expected)
    }
}
#endif
