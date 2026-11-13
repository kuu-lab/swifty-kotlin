#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmIterableFlattenPreservesOrderAndLinksLegacyFacade() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun flattenGroups(groups: Iterable<Iterable<String?>>): List<String?> = groups.flatten()

            fun main() {
                println(flattenGroups(listOf(listOf("a", null), emptyList(), listOf("b", "a"))))
                println(flattenGroups(emptyList()))
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [stdlib.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "[a, null, b, a]\n[]\n")

            try """
            import java.util.Arrays;
            import java.util.Collections;
            import kotlin.collections.CollectionsKt;

            public class Caller {
                public static void main(String[] args) {
                    System.out.println(CollectionsKt.flatten(Arrays.asList(
                        Arrays.asList(3, 5), Collections.emptyList(), Collections.singletonList(7))));
                }
            }
            """.write(to: root.appendingPathComponent("Caller.java"), atomically: true, encoding: .utf8)
            let compile = try jvmTool("javac", ["-cp", stdlib.path, "Caller.java"], root: root)
            try #require(compile.exitCode == 0, "\(compile.stderr)")
            let javaCall = try java(["-Xverify:all", "-cp", root.path + ":" + stdlib.path, "Caller"])
            #expect(javaCall.exitCode == 0, "\(javaCall.stderr)")
            #expect(javaCall.stdout == "[3, 5, 7]\n")
        }
    }
}
#endif
