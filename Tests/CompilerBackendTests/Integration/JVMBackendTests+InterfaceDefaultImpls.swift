#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func interfaceDefaultImplementationsMatchKotlinABI() throws {
        try withWorkspace { root in
            let result = try compile("""
            interface A { fun f() = "A"; val p2: String get() = "pA" }
            interface B : A { fun g() = "B"; val p3: String get() = "pB" }
            open class C : B
            class D : B { override fun f() = "D" }
            class E : C()
            fun main() {
                val b: B = C()
                println(b.f())
                println(b.p2)
                println(b.g())
                println(b.p3)
                println(D().f())
                println(D().p2)
            }
            """, root: root, mode: .jvmJar)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }

            let jar = root.appendingPathComponent("hello.jar")
            let archive = try ZipArchive(data: Data(contentsOf: jar))
            for name in ["A$DefaultImpls.class", "B$DefaultImpls.class"] {
                #expect(archive.entries.contains { $0.name == name })
            }

            let interface = try jvmTool("javap", ["-p", "-c", "-classpath", jar.path, "B"], root: root).stdout
            #expect(interface.contains("access$f$jd(B)"))
            #expect(interface.contains("access$getP2$jd(B)"))

            let defaults = try jvmTool("javap", ["-p", "-c", "-classpath", jar.path, "B$DefaultImpls"], root: root).stdout
            #expect(defaults.contains("g(B)"))
            #expect(defaults.contains("getP3(B)"))
            #expect(defaults.contains("f(B)"))
            #expect(defaults.contains("getP2(B)"))
            #expect(defaults.contains("B.access$g$jd"))
            #expect(defaults.contains("B.access$getP3$jd"))
            #expect(defaults.contains("B.access$f$jd"))
            #expect(defaults.contains("B.access$getP2$jd"))

            let implementation = try jvmTool("javap", ["-v", "-p", "-c", "-classpath", jar.path, "C"], root: root).stdout
            #expect(implementation.contains("ACC_BRIDGE"))
            #expect(implementation.contains("invokespecial") && implementation.contains("B.g"))
            #expect(implementation.contains("invokespecial") && implementation.contains("B.getP3"))
            #expect(implementation.contains("invokespecial") && implementation.contains("B.f"))
            #expect(implementation.contains("invokespecial") && implementation.contains("B.getP2"))

            let explicitOverride = try jvmTool("javap", ["-p", "-c", "-classpath", jar.path, "D"], root: root).stdout
            #expect(!explicitOverride.contains("B.f"))
            #expect(explicitOverride.contains("invokespecial") && explicitOverride.contains("B.getP2"))

            let inheritedClass = try jvmTool("javap", ["-p", "-classpath", jar.path, "E"], root: root).stdout
            #expect(!inheritedClass.contains("java.lang.String f()"))
            #expect(!inheritedClass.contains("java.lang.String getP2()"))

            #expect(try java(["-jar", jar.path]).stdout == "A\npA\nB\npB\nD\npA\n")

            try """
            public class JavaConsumer {
                public static void main(String[] args) {
                    B value = new C();
                    System.out.println(B.DefaultImpls.f(value));
                    System.out.println(B.DefaultImpls.getP2(value));
                    System.out.println(B.DefaultImpls.g(value));
                    System.out.println(B.DefaultImpls.getP3(value));
                }
            }
            """.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-classpath", jar.path, "JavaConsumer.java"], root: root)
            let javaRun = try java(["-classpath", root.path + ":" + jar.path, "JavaConsumer"])
            #expect(javaRun.stdout == "A\npA\nB\npB\n")
        }
    }
}
#endif
