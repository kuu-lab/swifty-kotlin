@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct CodegenHashSetSuperConstructorTests {
    @Test(arguments: [(false, 0), (false, 2), (true, 0), (true, 2)])
    func superclassConstructorsInitializeTheSubclass(useArtifact: Bool, optimization: Int) throws {
        if useArtifact {
            TestStdlibCache.shared.prepare()
            try #require(CompilerOptions.defaultStdlibLibraryPath != nil)
        }
        let source = """
        class CopySet : HashSet<Int>(listOf(1, 2))
        class ParameterCopy(elements: Collection<Int>) : HashSet<Int>(elements) {
            val initialSize = size
        }
        class SecondaryCopy : HashSet<Int> {
            constructor(elements: Collection<Int>) : super(elements)
            constructor() : this(listOf(4, 4, 5))
        }
        class CapacitySet(capacity: Int) : HashSet<Int>(capacity)
        class FactorSet(capacity: Int, factor: Float) :
            HashSet<Int>(capacity, factor)

        fun main() {
            val values = CopySet()
            println(values.size)
            println(values.contains(1))
            println(values.contains(2))

            val source = mutableListOf(1, 2, 2)
            val copy = ParameterCopy(source)
            println(copy.initialSize)
            source.add(3)
            println(copy.contains(3))
            copy.add(4)
            println(source.contains(4))
            println(copy.size)
            println(ParameterCopy(emptyList()).size)
            println(SecondaryCopy().size)
            println(SecondaryCopy(listOf(8, 8)).contains(8))

            val capacity = CapacitySet(0)
            println(capacity.size)
            capacity.add(7)
            println(capacity.contains(7))
            println(CapacitySet(16).size)
            println(FactorSet(0, 0.75f).size)
            println(FactorSet(16, Float.POSITIVE_INFINITY).size)
            try { CapacitySet(-1); println("accepted negative capacity") }
            catch (e: IllegalArgumentException) { println("rejected negative capacity") }
            try { FactorSet(-1, 0.75f); println("accepted negative factor capacity") }
            catch (e: IllegalArgumentException) { println("rejected negative factor capacity") }
            try { FactorSet(1, 0f); println("accepted zero factor") }
            catch (e: IllegalArgumentException) { println("rejected zero factor") }
            try { FactorSet(1, -1f); println("accepted negative factor") }
            catch (e: IllegalArgumentException) { println("rejected negative factor") }
            try { FactorSet(1, Float.NaN); println("accepted NaN factor") }
            catch (e: IllegalArgumentException) { println("rejected NaN factor") }

            println(HashSet(listOf(1, 2, 2)).size)
            println(HashSet<Int>(8, 0.75f).size)
            println(LinkedHashSet(listOf(1, 2, 2)).size)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "HashSetSuperConstructors",
            expected: "2\ntrue\ntrue\n2\nfalse\nfalse\n3\n0\n2\ntrue\n"
                + "0\ntrue\n0\n0\n0\nrejected negative capacity\n"
                + "rejected negative factor capacity\nrejected zero factor\n"
                + "rejected negative factor\nrejected NaN factor\n2\n0\n2\n",
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            allowDefaultStdlibLibrary: useArtifact
        )
    }
}
