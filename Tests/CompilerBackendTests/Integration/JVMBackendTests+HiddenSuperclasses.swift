#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    private func hiddenSuperclassFixture(_ root: URL) throws -> URL {
        let sources = [
            "Visible": "public interface Visible { int inherited(); default int defaultValue() { return 5; } }",
            "Generic": "public interface Generic<T> { int measure(T value); }",
            "GenericDefault": "public interface GenericDefault<T> { int echo(T value); }",
            "Ancestor": "public abstract class Ancestor<T> { public int ancestor() { return 40; } public abstract int accept(T value); }",
            "Base": """
            interface HiddenDefault extends GenericDefault<String> {
                default int hiddenDefault() { return 6; }
                default int echo(String value) { return value.length() + 70; }
            }
            class Base extends Ancestor<String> implements Visible, HiddenDefault, Generic<String> {
                public int inherited() { return 7; }
                public final int fixed() { return 17; }
                public final int getFixedSize() { return 19; }
                public int choose(int value) { return value + 10; }
                public int choose(String value) { return value.length() + 20; }
                public int measure(String value) { return value.length() + 50; }
                public int accept(String value) { return value.length() + 60; }
                public static int staticValue() { return 31; }
                protected int protectedValue() { return 90; }
                int packageValue() { return 91; }
                private int privateValue() { return 92; }
            }
            """,
            "Child": "public class Child extends Base { public int choose(int value) { return value + 100; } }",
            "FinalChild": "public final class FinalChild extends Base {}",
            "Enclosing": "public class Enclosing { static class NestedBase { public int nested() { return 88; } } }",
            "NestedChild": "public class NestedChild extends Enclosing.NestedBase {}",
            "CovariantChild": """
            interface A { default Object value() { return "a"; } }
            interface B extends A { default String value() { return "b"; } }
            public class CovariantChild implements A, B {}
            """,
            "ReverseChild": "public class ReverseChild implements B, A {}",
        ]
        for (name, source) in sources {
            try ("package dep;\n" + source).write(to: root.appendingPathComponent(name + ".java"), atomically: true, encoding: .utf8)
        }
        _ = try jvmTool("javac", ["--release", "8", "-d", "deps"] + sources.keys.sorted().map { $0 + ".java" }, root: root)
        _ = try jvmTool("jar", ["cf", "deps.jar", "-C", "deps", "."], root: root)
        return root.appendingPathComponent("deps.jar")
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func importsPublicMethodsThroughHiddenSuperclasses(mode: EmitMode) throws {
        try withWorkspace { root in
            let dependency = try hiddenSuperclassFixture(root)
            let classpath = mode == .jvmJar ? dependency.path : root.appendingPathComponent("deps").path
            let index = try JVMClasspathIndex.load([classpath])
            #expect(index.classes["dep/Base"] == nil)
            #expect(index.classes["dep/HiddenDefault"] == nil)
            #expect(index.classes["dep/Enclosing$NestedBase"] == nil)
            let child = try #require(index.classes["dep/Child"])
            #expect(child.superclass == "dep/Ancestor")
            #expect(child.methods.contains { $0.name == "inherited" && $0.owner == "dep/Child" })
            #expect(child.methods.contains { $0.name == "fixed" && $0.isFinal })
            #expect(!child.methods.contains { ["protectedValue", "packageValue", "privateValue"].contains($0.name) })
            let source = """
            import dep.Child
            import dep.FinalChild
            import dep.Visible
            import dep.NestedChild
            import dep.CovariantChild
            import dep.ReverseChild
            class KotlinChild : Child() { override fun choose(p0: Int): Int = p0 + 200 }
            fun main() {
                val child = Child()
                println(child.inherited())
                println(child.choose(2)); println(child.choose("abc"))
                println(child.ancestor()); println(child.defaultValue())
                println(child.hiddenDefault()); println(child.measure("x")); println(child.accept("xx"))
                println(child.echo("xxx"))
                println(Child.staticValue())
                val visible: Visible = child
                println(visible.inherited()); println(visible.defaultValue())
                println(NestedChild().nested())
                println(CovariantChild().value().length); println(ReverseChild().value().length)
                println(child.fixed()); println(KotlinChild().choose(2))
                println(FinalChild().inherited())
                println(child.fixedSize)
            }
            """
            let result = try compile(source, root: root, mode: mode, classpath: [classpath])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let expected = "7\n102\n23\n40\n5\n6\n51\n62\n73\n31\n7\n5\n88\n1\n1\n17\n202\n7\n19\n"
            let execution = try java(["-cp", artifact + ":" + dependency.path, "HelloKt"])
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)
            _ = try jvmTool("kotlinc", ["hello.kt", "-classpath", dependency.path, "-include-runtime", "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + dependency.path, "HelloKt"])
            #expect(reference.stdout == expected)
            #expect(reference.stderr.isEmpty)
        }
    }

    @Test
    func hiddenSuperclassImportKeepsNonPublicDeclarationsInaccessible() throws {
        try withWorkspace { root in
            let dependency = try hiddenSuperclassFixture(root)
            for expression in ["dep.Base()", "dep.HiddenDefault", "dep.Child().protectedValue()", "dep.Child().packageValue()", "dep.Child().privateValue()"] {
                let result = try compile("fun main() { println(\(expression)) }", root: root, mode: .jvmJar, classpath: [dependency.path])
                #expect(result.0 == 1, "\(expression)")
                #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") }, "\(expression)")
            }
            let finalOverride = try compile("class Derived : dep.Child() { override fun fixed(): Int = 9 }", root: root, mode: .jvmJar, classpath: [dependency.path])
            #expect(finalOverride.0 == 1)
            #expect(finalOverride.1.contains { $0.severity == .error && $0.message.contains("final") })
            let finalSubclass = try compile("class Derived : dep.FinalChild()", root: root, mode: .jvmJar, classpath: [dependency.path])
            #expect(finalSubclass.0 == 1)
            #expect(finalSubclass.1.contains { $0.severity == .error && $0.message.contains("final") })
            let finalProperty = try compile("class Derived : dep.Child() { override val fixedSize: Int get() = 9 }", root: root, mode: .jvmJar, classpath: [dependency.path])
            #expect(finalProperty.0 == 1)
            #expect(finalProperty.1.contains { $0.severity == .error && $0.message.contains("final") })
        }
    }
}
#endif
