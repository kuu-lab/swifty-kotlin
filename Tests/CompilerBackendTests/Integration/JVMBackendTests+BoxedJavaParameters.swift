#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaBoxedParametersAreDistinctFromPrimitiveOverloads() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            // Model a platform classpath that indexes the boxed carrier.
            // At execution the JVM resolves Boolean from its bootstrap loader.
            try """
            package java.lang; public final class Boolean {}
            """.write(to: root.appendingPathComponent("Boolean.java"), atomically: true, encoding: .utf8)
            try """
            package fixture;
            public final class BoxedSwitch {
                public static void enabled(boolean flag) { System.out.println("primitive:" + flag); }
                public static void enabled(Boolean flag) { System.out.println("boxed:" + flag); }
                public static void boxed(Boolean flag) { System.out.println("only-boxed:" + flag); }
            }
            """.write(to: root.appendingPathComponent("BoxedSwitch.java"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("javac", ["--release", "8", "-d", "platform", "Boolean.java", "BoxedSwitch.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let platform = root.appendingPathComponent("platform").path
            let classpath = [platform, library.path]
            let source = """
            import fixture.BoxedSwitch
            fun main() {
                BoxedSwitch.enabled(true)
                BoxedSwitch.boxed(null)
                BoxedSwitch.boxed(false)
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let result = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "primitive:true\nonly-boxed:null\nonly-boxed:false\n")
        }
    }
}
#endif
