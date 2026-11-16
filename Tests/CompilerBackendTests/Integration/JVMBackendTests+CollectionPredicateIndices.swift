#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func collectionPredicateIndicesMatchTraversalAndFailure() throws {
        try withWorkspace { root in
            let source = """
            fun main() {
                val values = listOf(1, 2, 3, 2)
                val iterable: Iterable<Int> = values
                println(values.indexOfFirst { it == 2 })
                println(values.indexOfLast { it == 2 })
                println(values.indexOfFirst { it == 5 })
                println(iterable.indexOfFirst { it > 2 })
                println(iterable.indexOfLast { it == 2 })
                val empty: List<Int> = java.util.ArrayList<Int>()
                println(empty.indexOfLast { true })
            }
            """
            let (app, status, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar")
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path, "MainKt"])
            #expect(run.stdout == "1\n3\n-1\n2\n3\n-1\n")
        }
    }
}
#endif
