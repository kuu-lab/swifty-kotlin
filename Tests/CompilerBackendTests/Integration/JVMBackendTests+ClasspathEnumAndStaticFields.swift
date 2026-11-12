#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedEnumsAndMutableStaticFieldsUseTheirClassfileMembers() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package api;
            public final class Resources {
                public enum Day { FIRST, SECOND }
                public static final class raw {
                    public static int agenda = 17;
                }
            }
            """
            try dependency.write(to: root.appendingPathComponent("Resources.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes")
            try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)
            let compiled = try jvmTool("javac", ["-d", classes.path, "Resources.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let source = """
            import api.Resources
            import api.Resources.Day
            fun label(day: Day): String = when (day) {
                Day.FIRST -> "first"
                Day.SECOND -> "second"
            }
            fun main() {
                println(label(Day.SECOND))
                println(Resources.raw.agenda)
                Resources.raw.agenda = 25
                Resources.raw.agenda += 2
                println(Resources.raw.agenda)
            }
            """
            let classpath = [classes.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "second\n17\n27\n")
        }
    }
}
#endif
