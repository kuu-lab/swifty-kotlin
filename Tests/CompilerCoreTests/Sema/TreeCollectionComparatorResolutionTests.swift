@testable import CompilerCore
import Testing

@Suite
struct TreeCollectionComparatorResolutionTests {
    @Test
    func jvmTreeSetAndTreeMapComparatorOverridesResolve() throws {
        let source = """
        fun <T> compareBy(selector: (T) -> Comparable<*>?): Comparator<T> = null!!

        fun main() {
            val ts = java.util.TreeSet(compareBy<Int> { it })
            println(ts.comparator())
            val tm: java.util.TreeMap<Int, Int> = java.util.TreeMap(compareBy<Int> { it })
            println(tm.comparator())
        }
        """
        let context = makeContextFromSource(source, emit: .jvmJar)
        try JVMPreparationPhase().run(context)
        try runSema(context)

        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected JVM TreeSet/TreeMap comparator overrides to resolve: \(errors)")
    }
}
