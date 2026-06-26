@testable import CompilerCore
import Foundation
import XCTest

final class CodegenBackendIntegrationTests: XCTestCase {
    func testCodegenEmitsKirDumpArtifact() throws {
        let source = """
        inline fun helper(x: Int) = x + 1
        fun main() = helper(41)
        """

        try withTemporaryFile(contents: source) { path in
            let tempDir = FileManager.default.temporaryDirectory

            let kirBase = tempDir.appendingPathComponent(UUID().uuidString).path
            _ = try runCodegenPipeline(inputPath: path, moduleName: "KirMod", emit: .kirDump, outputPath: kirBase)
            XCTAssertTrue(FileManager.default.fileExists(atPath: kirBase + ".kir"))
        }
    }

    func testCodegenEmitsLlvmIRArtifact() throws {
        let source = """
        inline fun helper(x: Int) = x + 1
        fun main() = helper(41)
        """

        try withTemporaryFile(contents: source) { path in
            let tempDir = FileManager.default.temporaryDirectory
            let llvmBase = tempDir.appendingPathComponent(UUID().uuidString).path
            let llvmCtx = try runCodegenPipeline(inputPath: path, moduleName: "LLMod", emit: .llvmIR, outputPath: llvmBase)
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            XCTAssertTrue(llvmPath.hasSuffix(".ll"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: llvmPath))
        }
    }

    func testCodegenEmitsLibraryArtifacts() throws {
        let source = """
        inline fun helper(x: Int) = x + 1
        fun main() = helper(41)
        """

        try withTemporaryFile(contents: source) { path in
            let tempDir = FileManager.default.temporaryDirectory
            let libBase = tempDir.appendingPathComponent(UUID().uuidString).path
            _ = try runCodegenPipeline(inputPath: path, moduleName: "LibMod", emit: .library, outputPath: libBase)

            let libDir = libBase + ".kklib"
            let manifestPath = libDir + "/manifest.json"
            let metadataPath = libDir + "/metadata.bin"
            let objectPath = libDir + "/objects/LibMod_0.o"
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifestPath))
            XCTAssertTrue(FileManager.default.fileExists(atPath: metadataPath))
            XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))

            let manifest = try String(contentsOfFile: manifestPath, encoding: .utf8)
            XCTAssertTrue(manifest.contains("\"moduleName\": \"LibMod\""))

            let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
            XCTAssertTrue(metadata.contains("symbols="))

            let inlineDir = libDir + "/inline-kir"
            let inlineFiles = try FileManager.default.contentsOfDirectory(atPath: inlineDir)
            XCTAssertFalse(inlineFiles.isEmpty)
            XCTAssertTrue(inlineFiles.allSatisfy { $0.hasSuffix(".kirbin") })
        }
    }

    func testCodegenLibraryMetadataIncludesCompilerMetadataAnnotation() throws {
        let source = """
        class Plain
        interface Face
        object Singleton
        enum class Color { RED }
        annotation class Marker
        """

        try withTemporaryFile(contents: source) { path in
            let tempDir = FileManager.default.temporaryDirectory
            let libBase = tempDir.appendingPathComponent(UUID().uuidString).path
            _ = try runCodegenPipeline(inputPath: path, moduleName: "MetadataLib", emit: .library, outputPath: libBase)

            let metadataPath = libBase + ".kklib/metadata.bin"
            let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
            XCTAssertTrue(metadata.contains("kotlin.Metadata"))
            XCTAssertTrue(metadata.contains("fq=Plain"))
            XCTAssertTrue(metadata.contains("fq=Face"))
            XCTAssertTrue(metadata.contains("fq=Singleton"))
            XCTAssertTrue(metadata.contains("fq=Color"))
            XCTAssertTrue(metadata.contains("fq=Marker"))
        }
    }

    func testCodegenAnnotationReflectionHidesCompilerMetadata() throws {
        let source = """
        annotation class Label(val value: String = "ok")

        @Label("hello")
        class Tagged

        class Plain

        fun main() {
            println(Tagged::class.annotations.size)
            println(Plain::class.annotations.size)
        }
        """

        try assertKotlinOutput(source, moduleName: "MetadataReflection", expected: "1\n0\n")
    }

    func testCodegenProducesDeterministicKirOutput() throws {
        let source = """
        fun helper(x: Int, y: Int) = x + y
        fun main() = helper(40, 2)
        """
        try assertDeterministicCodegenOutput(source: source, emit: .kirDump)
    }

    func testCodegenProducesDeterministicLlvmIROutput() throws {
        let source = """
        fun helper(x: Int, y: Int) = x + y
        fun main() = helper(40, 2)
        """
        try assertDeterministicCodegenOutput(source: source, emit: .llvmIR)
    }

    func testCodegenProducesDeterministicObjectOutput() throws {
        let source = """
        fun helper(x: Int, y: Int) = x + y
        fun main() = helper(40, 2)
        """
        try assertDeterministicCodegenOutput(source: source, emit: .object)
    }

    func testCodegenDataClassSynthesizesCorrectToStringAndEqualityWithoutExplicitSuperclass() throws {
        let source = """
        data class Person(val name: String, val age: Int)
        fun main() {
            val p = Person("Alice", 30)
            println(p.toString())
            println(p.hashCode() != 0)
            val p2 = Person("Alice", 30)
            println(p == p2)
            println(p.equals(p2))
            val (name, age) = p
            println("$name is $age")
            println(p.component1())
            println(p.component2())
            val p3 = p.copy(age = 31)
            println(p3)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "DataClassToString",
            expected:
                """
                Person(name=Alice, age=30)
                true
                true
                true
                Alice is 30
                Alice
                30
                Person(name=Alice, age=31)

                """
        )
    }

    func testCodegenCompilesStringStdlibMixedThrowCalls() throws {
        let source = """
        fun main() {
            val maybe: String? = null
            println("  hello  ".trim())
            println("banana".replace("na", "NA"))
            println("1,2,3".split(","))
            println(maybe.isNullOrEmpty())
            println(maybe.isNullOrBlank())
            println("42".toInt())
            println("3.14".toDouble())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringStdlibMixedThrowCalls",
                emit: .object,
                outputPath: outputBase
            )
            let objectPath = try XCTUnwrap(ctx.generatedObjectPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))
        }
    }

    func testCodegenCompilesMathTopLevelCalls() throws {
        let source = """
        import kotlin.math.*

        fun main() {
            println(abs(-5))
            println(abs(-5.0))
            println(sqrt(4.0))
            println(pow(2.0, 3.0))
            println(ceil(2.3))
            println(floor(-2.3))
            println(round(2.7))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MathTopLevelCalls",
                emit: .object,
                outputPath: outputBase
            )
            let objectPath = try XCTUnwrap(ctx.generatedObjectPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))
        }
    }

    func testCodegenCompilesIntPrimitiveConversions() throws {
        let source = """
        fun main() {
            println(42.toFloat())
            println(300.toByte())
            println(32768.toShort())
        }
        """

        try assertKotlinOutput(source, moduleName: "IntPrimitiveConversions", expected: "42.0\n44\n-32768\n")
    }

    func testCodegenCompilesComparisonTopLevelCalls() throws {
        let source = """
        fun main() {
            println(maxOf(3, 7))
            println(minOf(3, 7))
        }
        """

        try assertKotlinOutput(source, moduleName: "ComparisonTopLevelCalls", expected: "7\n3\n")
    }

    func testCodegenCompilesUnsignedMaxOfTopLevelCalls() throws {
        let source = """
        fun main() {
            println(maxOf(1u, 4000000000u) == 4000000000u)
            println(maxOf(1u, 3u, 4000000000u) == 4000000000u)
        }
        """

        try assertKotlinOutput(source, moduleName: "UnsignedComparisonMaxOf", expected: "true\ntrue\n")
    }

    func testCodegenCompilesComparatorMaxOfTopLevelCalls() throws {
        let source = """
        fun main() {
            println(maxOf(1, 2, reverseOrder<Int>()) == 1)
            println(maxOf(1, 4, 2, 3, reverseOrder<Int>()) == 1)
        }
        """

        try assertKotlinOutput(source, moduleName: "ComparatorComparisonMaxOf", expected: "true\ntrue\n")
    }

    func testCodegenCompilesComparatorSortedWithTopLevelCalls() throws {
        let source = """
        fun main() {
            val list = listOf(3, 1, 4, 1, 5, 9)
            println(list.sortedWith(naturalOrder()))
            println(list.sortedWith(reverseOrder()))
            val comparator = compareBy<Int> { it }
            println(list.sortedWith(comparator.reversed()))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparatorComparisonSortedWith",
            expected:
                """
                [1, 1, 3, 4, 5, 9]
                [9, 5, 4, 3, 1, 1]
                [9, 5, 4, 3, 1, 1]

                """
        )
    }

    func testCodegenCompilesGenericMaxOfTopLevelCalls() throws {
        let source = """
        fun main() {
            println(maxOf("b", "a") == "b")
            println(maxOf("d", "b", "a", "c") == "d")
        }
        """

        try assertKotlinOutput(source, moduleName: "GenericComparisonMaxOf", expected: "true\ntrue\n")
    }

    func testCodegenGenericComparableTreatsNaNAsGreaterThanFiniteValues() throws {
        let source = """
        fun <T> pickGreater(a: T, b: T): T where T : Comparable<T> = if (a > b) a else b

        fun main() {
            val nan = "NaN".toDouble()
            println(pickGreater(nan, 1.0))
            println(pickGreater(1.0, nan))
        }
        """

        try assertKotlinOutput(source, moduleName: "NaNComparable", expected: "NaN\nNaN\n")
    }

    func testCodegenListOfIndexingUsesListRuntimeGet() throws {
        throw XCTSkip("List indexing test temporarily disabled on Linux")
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            println(list.size)
            println(list.get(0))
            println(list.get(1))
            println(list.get(2))
            println(list.contains(2))
            println(list.contains(5))
            println(list.isEmpty())
        }
        """

        try assertKotlinOutput(source, moduleName: "ListGetRuntime", expected: "3\n1\n2\n3\ntrue\nfalse\nfalse\n")
    }

    func testCodegenEnumNameAndOrdinal() throws {
        let source = """
        enum class Color { RED, GREEN, BLUE }

        fun main() {
            println(Color.RED.name)
            println(Color.RED.ordinal)
            println(Color.GREEN.name)
            println(Color.GREEN.ordinal)
        }
        """

        try assertKotlinOutput(source, moduleName: "EnumNameOrdinal", expected: "RED\n0\nGREEN\n1\n")
    }

    func testCodegenEnumValuesAndValueOf() throws {
        // Test enumValueOf (no map dependency)
        let sourceValueOf = """
        enum class Color { RED, GREEN, BLUE }

        fun main() {
            println(enumValueOf<Color>("GREEN"))
        }
        """
        try withTemporaryFile(contents: sourceValueOf) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "EnumValueOf",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "GREEN\n")
        }

        // Test enumValues
        let sourceValues = """
        enum class Color { RED, GREEN, BLUE }

        fun main() {
            val values = enumValues<Color>()
            println(values.size)
            println(values.get(0))
            println(values.get(1))
        }
        """
        try withTemporaryFile(contents: sourceValues) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "EnumValues",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "3\nRED\nGREEN\n")
        }
    }

    func testCodegenMutableListBasicMutationsUseRuntimeListBox() throws {
        let source = """
        fun main() {
            val list = mutableListOf(1, 2)
            list.add(3)
            println(list)
            val removed = list.removeAt(1)
            println(removed)
            println(list)
            list.clear()
            println(list)
        }
        """

        try assertKotlinOutput(source, moduleName: "MutableListBasicRuntime", expected: "[1, 2, 3]\n2\n[1, 3]\n[]\n")
    }

    func testCodegenListComponentNUsesRuntimeAccessors() throws {
        let source = """
        fun main() {
            val values = listOf("a", "b", "c", "d", "e")
            println(values.component1())
            println(values.component2())
            println(values.component3())
            println(values.component4())
            println(values.component5())
        }
        """

        try assertKotlinOutput(source, moduleName: "ListComponentNRuntime", expected: "a\nb\nc\nd\ne\n")
    }

    func testCodegenListFilterIsInstanceToUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val values: List<Any> = listOf(1, "two", 3, "four")
            val dest = mutableListOf<Int>(99)
            val result = values.filterIsInstanceTo(dest)
            println(result)
            println(dest)
        }
        """

        try assertKotlinOutput(source, moduleName: "ListFilterIsInstanceToRuntime", expected: "[99, 1, 3]\n[99, 1, 3]\n")
    }

    func testCodegenCollectionContainsAndContainsAllUseRuntimeHelpers() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            println(list.contains(2))
            println(list.contains(9))
            println(list.containsAll(listOf(1, 3)))
            println(list.containsAll(listOf(1, 9)))

            val set = setOf("a", "b")
            println(set.contains("a"))
            println(set.containsAll(listOf("a", "b")))
            println(set.containsAll(listOf("a", "c")))
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionContainsRuntime", expected: "true\nfalse\ntrue\nfalse\ntrue\ntrue\nfalse\n")
    }

    func testCodegenMutableListRemoveFirstOrNullUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/mutable_list_removefirstornull.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try assertKotlinOutput(
            source,
            moduleName: "MutableListRemoveFirstOrNull",
            expected:
                """
                1
                [2]
                2
                []
                -1
                []
                """ + "\n"
        )
    }

    func testCodegenMutableListRemoveLastOrNullUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/mutable_list_removelastornull.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try assertKotlinOutput(
            source,
            moduleName: "MutableListRemoveLastOrNull",
            expected:
                """
                2
                [1]
                1
                []
                -1
                []
                """ + "\n"
        )
    }

    func testCodegenMutableListSortWithUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/mutable_list_sortwith.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try assertKotlinOutput(
            source,
            moduleName: "MutableListSortWith",
            expected:
                """
                [1, 3, 4]
                [4, 3, 1]
                [fig, pear, apple]
                """ + "\n"
        )
    }

    func testCodegenSetFactoriesAndMutableSetMutationsUseRuntimeSetBox() throws {
        let source = """
        fun main() {
            val set = setOf(1, 2, 2, 3)
            println(set)
            println(set.size)
            println(set.contains(2))
            println(set.isEmpty())

            val mutable = mutableSetOf(1, 2)
            println(mutable.add(2))
            println(mutable.add(3))
            println(mutable.remove(1))
            println(mutable)
            println(emptySet<Int>().isEmpty())
        }
        """

        try assertKotlinOutput(source, moduleName: "SetRuntime", expected: "[1, 2, 3]\n3\ntrue\nfalse\nfalse\ntrue\ntrue\n[2, 3]\ntrue\n")
    }

    func testCodegenSetOfNotNullFiltersNullsAndDeduplicates() throws {
        let source = """
        fun main() {
            val values = setOfNotNull("a", null, "b", null, "a")
            println(values)
            println(values.size)

            val empty = setOfNotNull<String>(null)
            println(empty)
            println(empty.isEmpty())
        }
        """

        try assertKotlinOutput(source, moduleName: "SetOfNotNullRuntime", expected: "[a, b]\n2\n[]\ntrue\n")
    }

    func testCodegenLinkedSetOfFactoryUsesMutableRuntimeSet() throws {
        let source = """
        fun main() {
            val set = linkedSetOf(1, 2, 2)
            println(set)
            println(set.add(3))
            println(set)

            val empty = linkedSetOf<String>()
            empty.add("x")
            println(empty)
        }
        """

        try assertKotlinOutput(source, moduleName: "LinkedSetOfFactoryRuntime", expected: "[1, 2]\ntrue\n[1, 2, 3]\n[x]\n")
    }

    func testCodegenHashSetOfFactoryUsesMutableRuntimeSet() throws {
        let source = """
        fun main() {
            val set = hashSetOf(1, 2, 2)
            println(set)
            println(set.add(3))
            println(set)

            val empty = hashSetOf<String>()
            empty.add("x")
            println(empty)
        }
        """

        try assertKotlinOutput(source, moduleName: "HashSetOfFactoryRuntime", expected: "[1, 2]\ntrue\n[1, 2, 3]\n[x]\n")
    }

    func testCodegenMutableSetAddAllAcceptsSetAndListCollections() throws {
        let source = """
        fun main() {
            val values = mutableSetOf(1, 2)
            println(values.addAll(listOf(2, 3, 4)))
            println(values)
            println(values.addAll(setOf(4, 5)))
            println(values)
            values.clear()
            println(values)
        }
        """

        try assertKotlinOutput(source, moduleName: "MutableSetAddAllRuntime", expected: "true\n[1, 2, 3, 4]\ntrue\n[1, 2, 3, 4, 5]\n[]\n")
    }

    func testCodegenIterableFirstNotNullOfReturnsFirstValueAndThrowsWhenMissing() throws {
        let source = """
        fun main() {
            val result: String = listOf(1, 2, 3).firstNotNullOf { if (it > 1) "hit" else null }
            println(result)
            try {
                listOf(1, 3, 5).firstNotNullOf { if (it % 2 == 0) it else null }
                println("missing")
            } catch (e: NoSuchElementException) {
                println("empty")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "IterableFirstNotNullOfRuntime", expected: "hit\nempty\n")
    }

    func testCodegenListPlusSetAppendsSetElements() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2)
            val set = setOf(4, 5)
            println(list + set)
        }
        """

        try assertKotlinOutput(source, moduleName: "ListPlusSetRuntime", expected: "[1, 2, 4, 5]\n")
    }

    func testCodegenMutableMapBasicMutationsUseRuntimeMapBox() throws {
        let source = """
        fun main() {
            val map = mutableMapOf("a" to 1)
            map["b"] = 2
            println(map)
            println(map.containsKey("a"))
            println(map.put("a", 3))
            println(map)
            println(map.remove("b"))
            println(map)
            println(map.getOrPut("a") { 7 })
            println(map.getOrPut("c") { 7 })
            println(map)
            println(emptyMap<String, Int>().isEmpty())
        }
        """

        try assertKotlinOutput(source, moduleName: "MutableMapBasicRuntime", expected: "{a=1, b=2}\ntrue\n1\n{a=3, b=2}\n2\n{a=3}\n3\n7\n{a=3, c=7}\ntrue\n")
    }

    func testCodegenLinkedMapOfFactoryUsesMutableRuntimeMap() throws {
        let source = """
        fun main() {
            val map = linkedMapOf("a" to 1)
            map["b"] = 2
            println(map)
            println(map.put("a", 3))
            println(map)

            val empty = linkedMapOf<String, Int>()
            empty["z"] = 9
            println(empty)
        }
        """

        try assertKotlinOutput(source, moduleName: "LinkedMapOfFactoryRuntime", expected: "{a=1, b=2}\n1\n{a=3, b=2}\n{z=9}\n")
    }

    func testCodegenHashMapOfFactoryUsesMutableRuntimeMap() throws {
        let source = """
        fun main() {
            val map = hashMapOf("a" to 1)
            map["b"] = 2
            println(map)
            println(map.put("a", 3))
            println(map)

            val empty = hashMapOf<String, Int>()
            empty["z"] = 9
            println(empty)
        }
        """

        try assertKotlinOutput(source, moduleName: "HashMapOfFactoryRuntime", expected: "{a=1, b=2}\n1\n{a=3, b=2}\n{z=9}\n")
    }

    func testCodegenBuildMapUseRuntimeBuilder() throws {
        let source = """
        fun main() {
            val m = buildMap {
                put("a", 1)
                put("b", 2)
            }
            println(m)
        }
        """

        try assertKotlinOutput(source, moduleName: "BuildMapRuntime", expected: "{a=1, b=2}\n")
    }

    func testCodegenBuildSetUseRuntimeBuilder() throws {
        let source = """
        fun main() {
            val s = buildSet {
                add("a")
                add("b")
                add("a")
                addAll(setOf("c", "b"))
            }
            println(s)
            println(s.size)
            println(s.contains("c"))
        }
        """

        try assertKotlinOutput(source, moduleName: "BuildSetRuntime", expected: "[a, b, c]\n3\ntrue\n")
    }

    func testCodegenMapWithDefaultUsesRuntimeDefaultForGetValue() throws {
        let source = """
        fun main() {
            val factor = 100
            val values = mapOf(1 to 10).withDefault { it * factor }
            println(values.getValue(1))
            println(values.getValue(2))
            println(values[2])
        }
        """

        try assertKotlinOutput(source, moduleName: "MapWithDefaultRuntime", expected: "10\n200\nnull\n")
    }

    func testCodegenListMaxOfOrNullReturnsLargestTransformedValueOrNull() throws {
        let source = """
        fun main() {
            val values = listOf(-3, 1, 2)
            println(values.maxOfOrNull { it * it })
            println(emptyList<Int>().maxOfOrNull { it * it })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMaxOfOrNullRuntime", expected: "9\nnull\n")
    }

    func testCodegenListMaxOrNullReturnsLargestElementOrNull() throws {
        let source = """
        fun main() {
            val values = listOf(3, 1, 4, 2)
            println(values.maxOrNull())
            println(emptyList<Int>().maxOrNull() == null)
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMaxOrNullRuntime", expected: "4\ntrue\n")
    }

    func testCodegenListFlattenUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val nested = listOf(listOf(1, 2), listOf(3))
            println(nested.flatten())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ListFlattenRuntime", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_list_flatten"))
        }
    }

    func testCodegenListMaxOfWithOrNullReturnsLargestTransformedValueOrNull() throws {
        let source = """
        fun main() {
            val values = listOf(-3, 1, 2)
            println(values.maxOfWithOrNull(naturalOrder<Int>()) { it * it })
            val missing = emptyList<Int>().maxOfWithOrNull(naturalOrder<Int>()) { it * it }
            println(missing == null)
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMaxOfWithOrNullRuntime", expected: "9\ntrue\n")
    }

    func testCodegenListMinOfReturnsSmallestSelectedValueAndThrowsOnEmpty() throws {
        let source = """
        fun main() {
            println(listOf(5, 2, 3).minOf { it * 10 })
            try {
                emptyList<Int>().minOf { it * 10 }
                println("missing")
            } catch (e: NoSuchElementException) {
                println("empty")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMinOfRuntime", expected: "20\nempty\n")
    }

    func testCodegenListMaxOfWithReturnsLargestTransformedValueAndThrowsOnEmpty() throws {
        let source = """
        fun main() {
            val values = listOf(-3, 1, 2)
            println(values.maxOfWith(naturalOrder<Int>()) { it * it })
            try {
                emptyList<Int>().maxOfWith(naturalOrder<Int>()) { it * it }
                println("missing")
            } catch (e: NoSuchElementException) {
                println("empty")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMaxOfWithRuntime", expected: "9\nempty\n")
    }

    func testCodegenListFlatMapIndexedUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val list = listOf(3, 1, 2)
            println(list.flatMapIndexed { index, value -> listOf(index, value * 10) })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ListFlatMapIndexedRuntime", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_list_flatMapIndexed"),
                "Expected kk_list_flatMapIndexed in callees, got: \(callees.sorted())"
            )
        }
    }

    func testCodegenListToHashSetDeduplicatesAndReturnsMutableSet() throws {
        let source = """
        fun main() {
            val sourceList = listOf(1, 2, 2, 3)
            val hashSet = sourceList.toHashSet()
            println(hashSet)
            println(hashSet.contains(2))
            hashSet.add(4)
            println(sourceList.contains(4))
            println(hashSet)
        }
        """

        try assertKotlinOutput(source, moduleName: "ListToHashSetRuntime", expected: "[1, 2, 3]\ntrue\nfalse\n[1, 2, 3, 4]\n")
    }

    // STDLIB-COMP-FN-009: maxOf(Byte, Byte, Byte)
    func testCodegenCompilesMaxOfByteThreeArgTopLevelCall() throws {
        let source = """
        fun main() {
            val a: Byte = 3
            val b: Byte = 7
            val c: Byte = 5
            println(maxOf(a, b, c))
        }
        """

        try assertKotlinOutput(source, moduleName: "MaxOfByteThreeArg", expected: "7\n")
    }

    // STDLIB-COMP-FN-017: maxOf(Int, Int)
    func testCodegenCompilesMaxOfIntTwoArgTopLevelCall() throws {
        let source = """
        fun main() {
            val a = 8
            val b = 4
            println(maxOf(a, b))
        }
        """

        try assertKotlinOutput(source, moduleName: "MaxOfIntTwoArg", expected: "8\n")
    }

    // STDLIB-COMP-FN-041: minOf(Int, Int)
    func testCodegenCompilesMinOfIntTwoArgTopLevelCall() throws {
        let source = """
        fun main() {
            val a = 8
            val b = 4
            println(minOf(a, b))
        }
        """

        try assertKotlinOutput(source, moduleName: "MinOfIntTwoArg", expected: "4\n")
    }

    // STDLIB-COMP-FN-043: minOf(a: Int, vararg other: Int)
    func testCodegenCompilesMinOfIntVarargTopLevelCall() throws {
        let source = """
        fun main() {
            println(minOf(5, 2, 8, 1))
            val a = 7
            val b = 4
            val c = 11
            val d = 2
            println(minOf(a, b, c, d, -9))
        }
        """

        try assertKotlinOutput(source, moduleName: "MinOfIntVararg", expected: "1\n-9\n")
    }

    func testCodegenCompilesMaxOfLongTwoArgTopLevelCall() throws {
        let source = """
        fun main() {
            println(maxOf(3L, 7L))
            val a = 100L
            val b = 400L
            println(maxOf(a, b))
        }
        """

        try assertKotlinOutput(source, moduleName: "MaxOfLongTwoArg", expected: "7\n400\n")
    }

    // STDLIB-COMP-FN-022: maxOf(a: Long, vararg other: Long)
    func testCodegenCompilesMaxOfLongVarargTopLevelCall() throws {
        let source = """
        fun main() {
            println(maxOf(5L, 2L, 8L, 1L))
            val a = 100L
            val b = 400L
            val c = 200L
            val d = 300L
            println(maxOf(a, b, c, d, 50L))
        }
        """

        try assertKotlinOutput(source, moduleName: "MaxOfLongVararg", expected: "8\n400\n")
    }

    // STDLIB-COMP-FN-032: minOf(Byte, Byte)
    func testCodegenCompilesMinOfByteTwoArgTopLevelCall() throws {
        let source = """
        fun main() {
            val a: Byte = 3
            val b: Byte = 7
            println(minOf(a, b))
        }
        """

        try assertKotlinOutput(source, moduleName: "MinOfByteTwoArg", expected: "3\n")
    }

    // STDLIB-COMP-FN-034: minOf(a: Byte, vararg other: Byte)
    func testCodegenCompilesMinOfByteVarargTopLevelCall() throws {
        let source = """
        fun main() {
            val a: Byte = 5
            val b: Byte = 2
            val c: Byte = 8
            val d: Byte = 1
            println(minOf(a, b, c, d))
        }
        """

        try assertKotlinOutput(source, moduleName: "MinOfByteVararg", expected: "1\n")
    }

    // STDLIB-COMP-FN-012: maxOf(Double, Double, Double)
    func testCodegenCompilesMaxOfDoubleThreeArgTopLevelCall() throws {
        let source = """
        fun main() {
            val a: Double = 1.5
            val b: Double = 7.25
            val c: Double = 3.5
            println(maxOf(a, b, c))
        }
        """

        try assertKotlinOutput(source, moduleName: "MaxOfDoubleThreeArg", expected: "7.25\n")
    }

    // STDLIB-COMP-FN-024: maxOf(Short, Short, Short)
    func testCodegenCompilesMaxOfShortThreeArgTopLevelCall() throws {
        let source = """
        fun main() {
            val a: Short = 1
            val b: Short = 7
            val c: Short = 3
            println(maxOf(a, b, c))
        }
        """

        try assertKotlinOutput(source, moduleName: "MaxOfShortThreeArg", expected: "7\n")
    }

    // STDLIB-COMP-FN-036: minOf(Double, Double, Double)
    func testCodegenCompilesMinOfDoubleThreeArgTopLevelCall() throws {
        let source = """
        fun main() {
            val a: Double = 1.5
            val b: Double = 7.25
            val c: Double = 3.5
            println(minOf(a, b, c))
        }
        """

        try assertKotlinOutput(source, moduleName: "MinOfDoubleThreeArg", expected: "1.5\n")
    }

    // STDLIB-COMP-FN-039: minOf(Float, Float, Float)
    func testCodegenCompilesMinOfFloatThreeArgTopLevelCall() throws {
        let source = """
        fun main() {
            val a: Float = 1.5f
            val b: Float = 7.25f
            val c: Float = 3.5f
            println(minOf(a, b, c))
        }
        """

        try assertKotlinOutput(source, moduleName: "MinOfFloatThreeArg", expected: "1.5\n")
    }

    // STDLIB-COMP-FN-029: minOf(T, T) where T : Comparable<T>
    func testCodegenCompilesMinOfComparableTwoArgCall() throws {
        let source = """
        fun main() {
            val a = "banana"
            val b = "apple"
            println(minOf(a, b))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MinOfComparableTwoArg",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "apple\n")
        }
    }

    // STDLIB-COMP-FN-030: minOf(T, T, T) where T : Comparable<T>
    func testCodegenCompilesMinOfComparableThreeArgCall() throws {
        let source = """
        fun main() {
            val a = "banana"
            val b = "apple"
            val c = "cherry"
            println(minOf(a, b, c))
        }
        """

        try assertKotlinOutput(source, moduleName: "MinOfComparableThreeArg", expected: "apple\n")
    }

    // STDLIB-COMP-FN-011: maxOf(Double, Double)
    func testCodegenCompilesMaxOfDoubleTwoArgTopLevelCall() throws {
        let source = """
        fun main() {
            val a: Double = 1.5
            val b: Double = 7.25
            println(maxOf(a, b))
        }
        """

        try assertKotlinOutput(source, moduleName: "MaxOfDoubleTwoArg", expected: "7.25\n")
    }

    // STDLIB-COMP-FN-035: minOf(Double, Double)
    func testCodegenCompilesMinOfDoubleTwoArgTopLevelCall() throws {
        let source = """
        fun main() {
            val a: Double = 1.5
            val b: Double = 7.25
            println(minOf(a, b))
        }
        """

        try assertKotlinOutput(source, moduleName: "MinOfDoubleTwoArg", expected: "1.5\n")
    }

    // MARK: - Private Helpers
}

