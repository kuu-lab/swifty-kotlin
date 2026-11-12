#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func androidClasspathUsesMutableResourceFieldsAndEnumSupertypes() throws {
        let info = JVMClassInfo(name: "Resources$raw", flags: 0x31, superclass: "java/lang/Object", interfaces: [], methods: [])
        #expect(info.isRuntimeStaticField(JVMForeignField(name: "agenda", descriptor: "I", access: 9, constantValue: .int(0))))
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package api;
            public final class Resources {
                public interface Period { int number(); }
                public enum Day implements Period {
                    FIRST, SECOND;
                    public int number() { return ordinal() + 1; }
                }
            }
            """
            try dependency.write(to: root.appendingPathComponent("Resources.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes")
            try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)
            let compiled = try jvmTool("javac", ["-d", classes.path, "Resources.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let source = """
            import api.Resources.Day
            import api.Resources.Period
            import java.util.Locale
            fun index(period: Period): Int = period.number()
            fun main() {
                println(index(Day.SECOND))
                println(Locale.forLanguageTag("ja-JP").language)
            }
            """
            let classpath = [classes.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "2\nja\n")
        }
    }
}
#endif
