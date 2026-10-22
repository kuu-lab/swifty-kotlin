#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mapOperatorsCopyEntriesWithoutAccessOrderMutation(mode: EmitMode) throws {
        let source = """
        import fixture.MapOracle
        fun plusPair() {
            val source = MapOracle.fresh() as Map<String, Int>
            println(source + ("d" to 4))
            println(source)
        }
        fun plusMap() {
            val source = MapOracle.fresh() as Map<String, Int>
            val extra = MapOracle.fresh() as Map<String, Int>
            println(source + extra)
            println(source); println(extra)
        }
        fun minusKey() {
            val source = MapOracle.fresh() as Map<String, Int>
            println(source - "b")
            println(source)
        }
        fun minusKeys() {
            val source = MapOracle.fresh() as Map<String, Int>
            println(source - listOf("a", "c"))
            println(source)
        }
        fun main() {
            plusPair(); plusMap(); minusKey(); minusKeys()
        }
        """
        let expected = "{a=1, b=2, c=3, d=4}\n{a=1, b=2, c=3}\n{a=1, b=2, c=3}\n{a=1, b=2, c=3}\n{a=1, b=2, c=3}\n{a=1, c=3}\n{a=1, b=2, c=3}\n{b=2}\n{a=1, b=2, c=3}\n"
        try withWorkspace { root in
            let fixture = """
            package fixture;
            import java.util.LinkedHashMap;
            import java.util.Map;
            public final class MapOracle {
                public static Object fresh() {
                    Map<String, Integer> result = new LinkedHashMap<>(16, 0.75f, true);
                    result.put("a", 1);
                    result.put("b", 2);
                    result.put("c", 3);
                    return result;
                }
            }
            """
            try fixture.write(to: root.appendingPathComponent("MapOracle.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-d", root.path, "MapOracle.java"], root: root)
            let library = try ownStdlibRuntime()
            let result = try compile(source, root: root, mode: mode, classpath: [root.path, library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + root.path + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)
            _ = try jvmTool("kotlinc", ["hello.kt", "-classpath", root.path, "-d", "official.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("official.jar").path + ":" + root.path + ":" + library.path, "HelloKt"])
            #expect(reference.stdout == expected)
            #expect(reference.stderr.isEmpty)
        }
    }
}
#endif
