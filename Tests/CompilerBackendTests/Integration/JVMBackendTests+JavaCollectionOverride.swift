#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func arrayListSubclassOverridesAndDispatchesOnJVM() throws {
        try assertJVM("""
        class A : ArrayList<Int>() {
            override fun add(element: Int): Boolean {
                println("override")
                return super.add(element)
            }
        }

        fun main() {
            val list: ArrayList<Int> = A()
            println(list.add(1))
        }
        """, "override\ntrue\n")
    }

    @Test
    func arrayListSubclassCallsInheritedMembersOnJVM() throws {
        try assertJVM("""
        class A : ArrayList<String>()

        fun main() {
            val a = A()
            println(a.add("x"))
            println(a.size)
            println(a[0])
            a[0] = "y"
            println(a[0])
        }
        """, "true\n1\nx\ny\n")
    }

    @Test
    func arrayListSubclassSuperIndexedAccessUsesBaseImplementationOnJVM() throws {
        try assertJVM("""
        class A : ArrayList<String>() {
            override fun get(index: Int): String = super[index]
            override fun set(index: Int, element: String): String {
                super[index] = element
                return element
            }
        }

        fun main() {
            val xs: ArrayList<String> = A()
            xs.add("x")
            println(xs[0])
            xs[0] = "y"
            println(xs[0])
        }
        """, "x\ny\n")
    }

    @Test
    func javaCollectionParameterAcceptsMutableOverride() throws {
        try withWorkspace { root in
            try """
            package fixture;
            import java.util.List;
            public abstract class Listener {
                public abstract void update(List<String> values);
                public static void fire(Listener listener, List<String> values) { listener.update(values); }
            }
            """.write(to: root.appendingPathComponent("Listener.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Listener.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let source = """
            import fixture.Listener
            class MutableListener : Listener() {
                override fun update(values: MutableList<String>) { values.add("callback") }
            }
            fun main() {
                val values = java.util.ArrayList<String>()
                values.add("first")
                Listener.fire(MutableListener(), values)
                println(values.size)
                println(values[1])
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [classes])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "2\ncallback\n")

            let rejected = """
            import fixture.Listener
            class Wrong : Listener() {
                override fun update(values: MutableList<Int>) {}
            }
            """
            let (_, status, errors) = try m22Build(root: root, sources: [("Wrong.kt", rejected)], name: "wrong.jar", classpath: [classes])
            #expect(status != 0)
            #expect(errors.contains { $0.code == "KSWIFTK-SEMA-OVERRIDE-NOTHING" })
        }
    }
}
#endif
