#if canImport(Testing)
import Testing

extension JVMBackendTests {
    @Test
    func lambdaLiteralsUseInvokeDynamicAndKeepLambdaSemantics() throws {
        try withWorkspace { root in
            let result = try compile("""
            fun constant(): () -> Int = { 5 }
            fun addBy(amount: Int): (Int) -> Int = { it + amount }
            fun unitAction(): () -> Unit = { println("unit") }
            fun main() {
                val doubled = { x: Int -> x * 2 }
                println(doubled(3))
                println(constant() === constant())
                val add = addBy(4)
                println(add(3))
                println(addBy(4) === addBy(4))
                val action = unitAction()
                action()
            }
            """, root: root, mode: .jvmJar)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }

            let jar = root.appendingPathComponent("hello.jar")
            let listing = try jvmTool("jar", ["tf", jar.path], root: root).stdout
            #expect(!listing.contains("$Lambda"))

            let bytecode = try jvmTool("javap", ["-p", "-v", "-cp", jar.path, "HelloKt"], root: root).stdout
            #expect(bytecode.contains("InvokeDynamic"))
            #expect(bytecode.contains("BootstrapMethods"))
            #expect(bytecode.contains("java/lang/invoke/LambdaMetafactory.metafactory"))

            try #"""
            public class InspectLambda {
                public static void main(String[] args) {
                    Object lambda = HelloKt.constant();
                    System.out.println(lambda.getClass().isSynthetic());
                }
            }
            """#.write(to: root.appendingPathComponent("InspectLambda.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar.path, "InspectLambda.java"], root: root)
            let reflection = try java(["-cp", root.path + ":" + jar.path, "InspectLambda"])
            #expect(reflection.stdout == "true\n")

            let execution = try java(["-jar", jar.path])
            #expect(execution.stdout == "6\ntrue\n7\nfalse\nunit\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
