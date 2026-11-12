#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func iterableFilterNotWorksWithBundledJVMStdlib() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun stop(values: Iterable<String?>): String {
                values.filterNot { if (it == null) return "early" else false }
                return "finished"
            }
            fun main() {
                val values: Iterable<String?> = listOf("first", null, "second", "first")
                println(values.filterNot { it == "first" })
                println(values.filterNot { true })
                println(emptyList<String>().filterNot { error("must not run") })
                println(stop(values))
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "MainKt"])
            #expect(run.stdout == "[null, second]\n[]\n[]\nearly\n")

            let caller = """
            import java.util.Arrays;
            import kotlin.collections.CollectionsKt;

            public class Caller {
                public static void main(String[] args) {
                    System.out.println(CollectionsKt.filterNot(Arrays.asList(1, 2, 3), n -> n > 1));
                }
            }
            """
            try caller.write(to: root.appendingPathComponent("Caller.java"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("javac", ["-cp", own.path, "Caller.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let javaCall = try java(["-Xverify:all", "-cp", root.path + ":" + own.path, "Caller"])
            #expect(javaCall.stdout == "[1]\n")
        }
    }
}
#endif
