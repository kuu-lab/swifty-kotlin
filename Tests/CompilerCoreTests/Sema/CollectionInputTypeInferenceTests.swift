@testable import CompilerCore
import Testing

/// KUU-3452: collection receiver type arguments must not be widened by an
/// incompatible search argument.
@Suite
struct CollectionInputTypeInferenceTests {
    @Test
    func rejectsMismatchedMapKeysAndListSearchElements() throws {
        let sources = [
            "fun probe() { val m = mapOf(1 to \"a\"); m.containsKey(\"1\") }",
            "fun probe() { val m = mapOf(1 to \"a\"); m.containsKey(1L) }",
            "fun probe() { val m = mapOf(1 to \"a\"); \"1\" in m }",
            "fun probe() { val m = mapOf(1 to \"a\"); m.contains(\"1\") }",
            "fun probe() { val m = mapOf(1 to \"a\"); Pair(1, 2) in m }",
            "fun probe() { val list = listOf(1, 2); list.indexOf(\"1\") }",
            "fun probe() { val list = listOf(1, 2); list.indexOf(1L) }",
            "fun probe() { val list = listOf(1, 2); list.lastIndexOf(\"1\") }",
            "fun probe() { 5 in 1.0..10.0 }",
        ]
        let contents = sources.enumerated().map { index, source in
            "package kuu3452.case\(index)\n\(source)\n"
        }

        try withTemporaryFiles(contents: contents) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            for (index, path) in paths.enumerated() {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(!errors.isEmpty, "Expected to reject case \(index): \(sources[index])")
            }
        }
    }

    @Test
    func keepsMatchingAndSubtypeSearchElementsValid() throws {
        let ctx = makeContextFromSource("""
        fun probe() {
            val intMap = mapOf(1 to "a")
            intMap.containsKey(1)
            1 in intMap
            intMap.contains(1)
            intMap[1]
            intMap.get(1)

            val intList = listOf(1, 2)
            intList.indexOf(1)
            intList.lastIndexOf(2)
            1 in intList
            intList.contains(1)

            val intSet = setOf(1, 2)
            1 in intSet
            intSet.contains(1)

            val numberList: List<Number> = listOf<Number>(1, 2)
            numberList.indexOf(1)
            numberList.lastIndexOf(2)

            1.0 in 1.0..10.0
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
