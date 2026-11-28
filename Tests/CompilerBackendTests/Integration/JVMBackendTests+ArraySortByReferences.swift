#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func m22BundledArraySortByFunctionReferences() throws {
        try withWorkspace { root in
            let library = try m22Build(root: root, name: "kswiftk-stdlib.jar", stdlib: true)
            try #require(library.1 == 0, "\(library.2.map(\.message))")
            let source = #"""
            fun main() {
                val values = arrayOf(1, 2)
                val sort: ((Int) -> Int?) -> Unit = values::sortBy
                sort { -it }
                println(values.toList())

                val sorted: ((Int) -> Int?) -> List<Int> = arrayOf(2, 1)::sortedByDescending
                println(sorted { it })

                val nullable: ((String) -> Int?) -> List<String> = arrayOf("a", "bb", "c")::sortedByDescending
                println(nullable { if (it.length == 1) null else it.length })
            }
            """#
            let app = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [library.0.path])
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            let execution = try java(["-cp", app.0.path + ":" + library.0.path, "MainKt"])
            #expect(execution.stdout == "[2, 1]\n[2, 1]\n[bb, a, c]\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
