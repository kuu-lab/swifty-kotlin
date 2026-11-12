#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func lazyKotlinFileFacadeCallablesResolveBySourceName() throws {
        try withWorkspace { root in
            try """
            package dep.links
            fun String?.asLink(): String = this ?: "missing"
            fun Int.asLink(): String = "id=$this"
            fun ordinary(value: String): String = value
            """.write(to: root.appendingPathComponent("Links.kt"), atomically: true, encoding: .utf8)
            let library = try jvmTool("kotlinc", ["Links.kt", "-d", "links.jar"], root: root)
            try #require(library.exitCode == 0, "\(library.stderr)")

            // Push the user classpath over the automatic lazy-injection threshold
            // without making AndroidX-sized fixtures part of the test.
            let fields = (0..<20_000).map { "public static int f\($0);" }.joined(separator: "\n")
            try "package dep;\npublic class Big {\n\(fields)\n}\n".write(
                to: root.appendingPathComponent("Big.java"), atomically: true, encoding: .utf8
            )
            let bigClasses = try jvmTool("javac", ["--release", "8", "-d", "big-classes", "Big.java"], root: root)
            try #require(bigClasses.exitCode == 0, "\(bigClasses.stderr)")
            let bigJar = try jvmTool("jar", ["cf", "big.jar", "-C", "big-classes", "."], root: root)
            try #require(bigJar.exitCode == 0, "\(bigJar.stderr)")

            let classpath = [
                root.appendingPathComponent("links.jar").path,
                root.appendingPathComponent("big.jar").path,
            ]
            let runtime = try m11Runtime()
            let cases: [(file: String, name: String, imports: String, call: String)] = [
                ("Main.kt", "named", "import dep.links.asLink\nimport dep.links.ordinary", "asLink"),
                ("Main.kt", "star", "import dep.links.*", "asLink"),
                ("Main.kt", "alias", "import dep.links.asLink as link\nimport dep.links.ordinary", "link"),
                ("Main.kt", "facade", "import dep.links.LinksKt\nimport dep.links.asLink\nimport dep.links.ordinary", "asLink"),
            ]
            for (file, name, imports, call) in cases {
                let source = """
                \(imports)
                fun main() {
                    val missing: String? = null
                    println("host".\(call)())
                    println(missing.\(call)())
                    println(7.\(call)())
                    println(ordinary("ok"))
                }
                """
                let app = try m22Build(root: root, sources: [(file, source)], name: "app-\(name).jar", classpath: classpath)
                try #require(app.1 == 0, "\(name): \(app.2.map(\.message))")
                let run = try java(["-cp", ([app.0.path] + classpath + [runtime]).joined(separator: ":"), "MainKt"])
                #expect(run.exitCode == 0, "\(name): \(run.stderr)")
                #expect(run.stdout == "host\nmissing\nid=7\nok\n", "\(name)")
                #expect(run.stderr.isEmpty, "\(name)")
            }
        }
    }
}
#endif
