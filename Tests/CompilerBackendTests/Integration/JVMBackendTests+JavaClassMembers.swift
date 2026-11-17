#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    /// Java classfile members that Kotlin exposes through mapped shapes:
    /// `static final` constants, JavaBeans get/set pairs, `isX()` accessors,
    /// nested SAM interfaces, and inherited accessor pairs.
    private func javaMembersFixture(_ root: URL) throws -> URL {
        let sources: [String: String] = [
            "Constants": """
            public class Constants {
                public static final int VERTICAL = 1;
                public static final int HORIZONTAL = 0;
                public static final String LABEL = "static-label";
                public static final long BIG = 1234567890123L;
                public static final boolean ENABLED = true;
            }
            """,
            "Widget": """
            public class Widget {
                private String text = "";
                private int count;
                private boolean active;
                public String getText() { return text; }
                public void setText(String v) { text = v; }
                public int getCount() { return count; }
                public void setCount(int v) { count = v; }
                public boolean isReady() { return count > 0; }
                public boolean isActive() { return active; }
                public void setActive(boolean value) { active = value; }
            }
            """,
            "Outer": """
            public class Outer {
                public interface Callback { void onEvent(int value); }
                private Callback callback;
                public void setCallback(Callback c) { callback = c; }
                public void fire(int v) { if (callback != null) callback.onEvent(v); }
            }
            """,
            "Base": """
            public class Base {
                private int value;
                public int getValue() { return value; }
                public void setValue(int v) { value = v; }
            }
            """,
            "Derived": """
            public class Derived extends Base {
                @Override public int getValue() { return super.getValue() * 2; }
            }
            """,
        ]
        for (name, source) in sources {
            try ("package dep;\n" + source).write(to: root.appendingPathComponent(name + ".java"), atomically: true, encoding: .utf8)
        }
        _ = try jvmTool("javac", ["--release", "8", "-d", "deps"] + sources.keys.sorted().map { $0 + ".java" }, root: root)
        _ = try jvmTool("jar", ["cf", "deps.jar", "-C", "deps", "."], root: root)
        return root.appendingPathComponent("deps.jar")
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func javaStaticConstantsBeanPropertiesSAMAndInheritedAccessors(mode: EmitMode) throws {
        try withWorkspace { root in
            let dependency = try javaMembersFixture(root)
            let index = try JVMClasspathIndex.load([dependency.path])
            #expect(index.classes["dep/Outer$Callback"] != nil)
            #expect(index.classes["dep/Constants"]?.fields.contains {
                $0.name == "VERTICAL" && $0.isStatic && $0.isFinal
            } == true)

            let source = """
            import dep.Constants
            import dep.Derived
            import dep.Outer
            import dep.Widget

            fun main() {
                println(Constants.VERTICAL)
                println(Constants.HORIZONTAL)
                println(Constants.LABEL)
                println(Constants.BIG)
                println(Constants.ENABLED)

                val w = Widget()
                w.text = "hi"
                println(w.text)
                w.count = 3
                println(w.count)
                println(w.isReady())
                println(w.isReady)
                w.isActive = true
                println(w.isActive)

                val o = Outer()
                var seen = -1
                o.setCallback { v -> seen = v }
                o.fire(42)
                println(seen)

                val d = Derived()
                d.value = 5
                println(d.value)
            }
            """
            let classpath = mode == .jvmJar ? dependency.path : root.appendingPathComponent("deps").path
            let result = try compile(source, root: root, mode: mode, classpath: [classpath])
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let run = try java(["-cp", output + ":" + dependency.path, "HelloKt"])
            #expect(run.stdout == "1\n0\nstatic-label\n1234567890123\ntrue\nhi\n3\ntrue\ntrue\ntrue\n42\n10\n")
            #expect(run.stderr.isEmpty)
        }
    }
}
#endif
