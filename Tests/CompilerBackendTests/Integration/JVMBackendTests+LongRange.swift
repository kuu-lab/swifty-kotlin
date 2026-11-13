#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmLongRangeMembershipAndIterationLinkWithRepositoryStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun ongoing(start: Long, end: Long, now: Long): Boolean = now in start..end
            fun main() {
                val start = 1518076800000L
                val end = start + 1L
                println(ongoing(start, end, start))
                println(ongoing(start, end, end))
                println(ongoing(start, end, end + 1L))
                println(ongoing(end, start, start))
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [stdlib.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "true\ntrue\nfalse\nfalse\n")

            try """
            import kotlin.ranges.LongProgression;
            import kotlin.ranges.LongRange;
            import kotlin.collections.LongIterator;

            public class Caller {
                public static void main(String[] args) {
                    LongRange range = new LongRange(Long.MAX_VALUE - 1L, Long.MAX_VALUE);
                    LongIterator iterator = range.iterator();
                    while (iterator.hasNext()) System.out.println(iterator.nextLong());
                    LongProgression descending = new LongProgression(6L, 1L, -2L);
                    for (Object value : (Iterable<?>) descending) System.out.println(value);
                }
            }
            """.write(to: root.appendingPathComponent("Caller.java"), atomically: true, encoding: .utf8)
            let compile = try jvmTool("javac", ["-cp", stdlib.path, "Caller.java"], root: root)
            try #require(compile.exitCode == 0, "\(compile.stderr)")
            let javaCall = try java(["-Xverify:all", "-cp", root.path + ":" + stdlib.path, "Caller"])
            #expect(javaCall.exitCode == 0, "\(javaCall.stderr)")
            #expect(javaCall.stdout == "9223372036854775806\n9223372036854775807\n6\n4\n2\n")
        }
    }
}
#endif
