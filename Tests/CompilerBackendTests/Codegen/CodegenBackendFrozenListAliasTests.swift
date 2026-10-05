@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CodegenBackendFrozenListAliasTests {
    private static let mutations: [(String, String, String)] = [
        ("MutableList<String>", "root", "target.add(\"c\")"),
        ("MutableList<String>", "root", "target.remove(\"a\")"),
        ("MutableList<String>", "root", "target.clear()"),
        ("MutableCollection<String>", "root", "target.add(\"c\")"),
        ("MutableCollection<String>", "root", "target.remove(\"a\")"),
        ("MutableCollection<String>", "root", "target.clear()"),
        ("MutableIterator<String>", "root.iterator()", "target.remove()"),
        ("MutableList<String>", "root.subList(0, 1)", "target.clear()"),
        ("MutableList<String>", "root.subList(0, 1)", "target.set(0, \"c\")"),
        ("MutableList<String>", "root", "target.remove(\"missing\")"),
        ("MutableCollection<String>", "root", "target.remove(\"missing\")"),
        ("MutableList<String>", "root", "target.addAll(emptyList<String>())"),
        ("MutableCollection<String>", "root", "target.addAll(emptyList<String>())"),
        ("MutableList<String>", "root", "target.removeAll(emptyList<String>())"),
        ("MutableCollection<String>", "root", "target.removeAll(emptyList<String>())"),
        ("MutableList<String>", "root", "target.retainAll(listOf(\"a\", \"b\"))"),
        ("MutableCollection<String>", "root", "target.retainAll(listOf(\"a\", \"b\"))"),
        ("MutableList<String>", "root", "target.add(0, \"c\")"),
        ("MutableList<String>", "root", "target.addAll(0, emptyList<String>())"),
        ("MutableList<String>", "root", "target.removeAt(0)"),
        ("MutableList<String>", "root", "target.set(0, \"c\")"),
        ("MutableListIterator<String>", "root.listIterator()", "target.set(\"c\")"),
        ("MutableListIterator<String>", "root.listIterator(0)", "target.add(\"c\")"),
        ("MutableList<String>", "root.subList(0, 2).subList(0, 1)", "target.clear()"),
        ("MutableList<String>", "root.asReversed()", "target.clear()"),
        ("MutableList<String>", "root.asReversed().subList(0, 1)", "target.set(0, \"c\")"),
        ("MutableIterator<String>", "root.subList(0, 1).iterator()", "target.remove()"),
        ("MutableListIterator<String>", "root.asReversed().listIterator(0)", "target.set(\"c\")"),
        ("MutableList<String>", "root.subList(0, 0)", "target.clear()"),
    ]

    @Test(arguments: [0, 1, 2])
    func frozenAliasesThrow(mode: Int) throws {
        var functions: [String] = []
        for (index, mutation) in Self.mutations.enumerated() {
            let (type, target, action) = mutation
            let next = type.contains("Iterator") ? "target.next()" : ""
            functions.append("""
            fun mutate\(index)(target: \(type)) {
                println("entered:\(index)")
                \(action)
            }
            fun case\(index)() {
                val root = ArrayList<String>()
                root.add("a")
                root.add("b")
                val target = \(target)
                \(next)
                val built = root.build()
                try {
                    mutate\(index)(target)
                    println("accepted")
                } catch (e: IllegalStateException) {
                    println("wrong exception")
                } catch (e: UnsupportedOperationException) {
                    println("rejected")
                }
                println(built.size)
                println(built[0])
                println(built[1])
            }
            """)
        }
        let source = "@file:Suppress(\"INVISIBLE_MEMBER\", \"INVISIBLE_REFERENCE\")\n"
            + functions.joined(separator: "\n")
            + "\nfun main() {\n"
            + Self.mutations.indices.map { "case\($0)()" }.joined(separator: "\n")
            + "\n}\n"
        let expected = Self.mutations.indices.map { "entered:\($0)\nrejected\n2\na\nb\n" }.joined()
        try withTemporaryFile(contents: source) { path in
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "FrozenListAliases",
                emit: .executable,
                outputPath: output,
                optLevel: mode == 2 ? .O2 : .O0,
                allowDefaultStdlibLibrary: mode != 0
            )
            try #require(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected)
        }
    }
}
