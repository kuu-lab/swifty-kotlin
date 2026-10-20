#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func smartCastImplicitReceiversUseTheSelectedMemberOwner(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM10("""
            sealed class Result {
                data class Ok(val value: Int) : Result()
                data class Err(val message: String) : Result()
            }
            fun Result.text(): String = when (this) {
                is Result.Ok -> "ok$value"
                is Result.Err -> "err:$message"
            }
            sealed class Root
            class Leaf(var value: Int) : Root() {
                fun describe(): String = "leaf$value"
            }
            fun Root.read(): Int = when (this) { is Leaf -> value }
            fun Root.mutate(): String = when (this) { is Leaf -> { value++; describe() } }
            fun Root.explicit(): Int = when (this) { is Leaf -> (this as Leaf).value }
            fun main() {
                println(listOf<Result>(Result.Ok(1), Result.Err("bad")).map { it.text() })
                val leaf: Root = Leaf(7)
                println(leaf.read())
                println(leaf.mutate())
                println(leaf.explicit())
            }
            """, expected: "[ok1, err:bad]\n7\nleaf8\n8\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func smartCastImplicitForeignReceiversUseTheImportedMemberOwner(mode: EmitMode) throws {
        try withWorkspace { root in
            let dependency = try javaFixture(root)
            let source = """
            import dep.Counter
            fun Any.read(): Int = if (this is Counter) add(0) else -1
            fun Any.explicit(): Int = if (this is Counter) (this as Counter).add(0) else -1
            fun main() {
                println(Counter(19).read())
                println(Counter(19).explicit())
                println("other".read())
            }
            """
            let result = try compile(source, root: root, mode: mode, classpath: [dependency.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let run = try java(["-cp", artifact.path + ":" + dependency.path, "HelloKt"])
            #expect(run.stdout == "19\n19\n-1\n")
            #expect(run.stderr.isEmpty)
            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", dependency.path, "-include-runtime", "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + dependency.path, "HelloKt"])
            #expect(reference.stdout == run.stdout)
        }
    }
}
#endif
