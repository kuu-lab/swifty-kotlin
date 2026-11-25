#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedKotlinObjectMembersResolveAndRun() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package fixture
            object Defaults {
                fun helper(): Int = 42
                val answer: Int get() = 7
            }
            """
            try dependency.write(to: root.appendingPathComponent("Dependency.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Dependency.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let cases = [
                ("Qualified.kt", """
                import fixture.Defaults
                fun main() {
                    println(Defaults.helper())
                    println(Defaults.answer)
                }
                """),
                ("Imported.kt", """
                import fixture.Defaults.helper
                import fixture.Defaults.answer
                fun main() {
                    println(helper())
                    println(answer)
                }
                """)
            ]
            let classpath = [library.path, stdlib.path]
            for (name, source) in cases {
                let mainClass = name.replacingOccurrences(of: ".kt", with: "Kt")
                let (app, exit, diagnostics) = try m22Build(
                    root: root,
                    sources: [(name, source)],
                    name: name.replacingOccurrences(of: ".kt", with: ".jar"),
                    classpath: classpath
                )
                try #require(exit == 0, "\(diagnostics.map(\.message))")
                let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), mainClass])
                #expect(run.exitCode == 0, "\(run.stderr)")
                #expect(run.stdout == "42\n7\n")
            }
        }
    }

    @Test
    func importedKotlinObjectStaticMembersRemainCallable() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package fixture
            object WithStatics {
                const val C: Int = 7
                @JvmStatic fun s(): Int = 9
                @JvmField val f: Int = 11
                val p: Int get() = 13
                fun m(): Int = 15
            }
            """
            try dependency.write(to: root.appendingPathComponent("Dependency.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Dependency.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let cases = [
                ("Qualified.kt", """
                import fixture.WithStatics
                fun main() {
                    println(WithStatics.C)
                    println(WithStatics.s())
                    println(WithStatics.f)
                    println(WithStatics.p)
                    println(WithStatics.m())
                }
                """),
                ("Imported.kt", """
                import fixture.WithStatics.C
                import fixture.WithStatics.s
                import fixture.WithStatics.f
                import fixture.WithStatics.p
                import fixture.WithStatics.m
                fun main() {
                    println(C)
                    println(s())
                    println(f)
                    println(p)
                    println(m())
                }
                """)
            ]
            let classpath = [library.path, stdlib.path]
            for (name, source) in cases {
                let mainClass = name.replacingOccurrences(of: ".kt", with: "Kt")
                let (app, exit, diagnostics) = try m22Build(
                    root: root,
                    sources: [(name, source)],
                    name: name.replacingOccurrences(of: ".kt", with: ".jar"),
                    classpath: classpath
                )
                try #require(exit == 0, "\(diagnostics.map(\.message))")
                let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), mainClass])
                #expect(run.exitCode == 0, "\(run.stderr)")
                #expect(run.stdout == "7\n9\n11\n13\n15\n")
            }
        }
    }
}
#endif
