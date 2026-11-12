#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func objectJvmFieldUsesStaticFieldsAndPreservesInstanceFields() throws {
        let source = """
        object Obj {
            @JvmField val value: Int = 42
            @JvmField var mutable: Int = 7
        }
        class Holder {
            @JvmField val exposed: Int = 11
            val ordinary: Int = 5
        }
        fun main() {}
        """
        let javaSource = #"""
        import java.lang.reflect.Field;
        import java.lang.reflect.Modifier;

        public class Probe {
            public static void main(String[] args) throws Exception {
                Class<?> objectType = Class.forName("Obj");
                Field value = objectType.getDeclaredField("value");
                int valueModifiers = value.getModifiers();
                System.out.println("valueModifiers=" + Modifier.isPublic(valueModifiers) + ":" + Modifier.isStatic(valueModifiers) + ":" + Modifier.isFinal(valueModifiers));
                System.out.println("value=" + value.getInt(null));

                Field mutable = objectType.getDeclaredField("mutable");
                int mutableModifiers = mutable.getModifiers();
                System.out.println("mutableModifiers=" + Modifier.isPublic(mutableModifiers) + ":" + Modifier.isStatic(mutableModifiers) + ":" + Modifier.isFinal(mutableModifiers));
                System.out.println("mutableBefore=" + mutable.getInt(null));
                mutable.setInt(null, 9);
                System.out.println("mutableAfter=" + mutable.getInt(null));

                Class<?> holderType = Class.forName("Holder");
                Object holder = holderType.getDeclaredConstructor().newInstance();
                Field exposed = holderType.getDeclaredField("exposed");
                int exposedModifiers = exposed.getModifiers();
                System.out.println("exposedModifiers=" + Modifier.isPublic(exposedModifiers) + ":" + Modifier.isStatic(exposedModifiers) + ":" + Modifier.isFinal(exposedModifiers));
                System.out.println("exposed=" + exposed.getInt(holder));

                Field ordinary = holderType.getDeclaredField("ordinary");
                int ordinaryModifiers = ordinary.getModifiers();
                ordinary.setAccessible(true);
                System.out.println("ordinaryModifiers=" + Modifier.isStatic(ordinaryModifiers) + ":" + Modifier.isFinal(ordinaryModifiers));
                System.out.println("ordinary=" + ordinary.getInt(holder));
            }
        }
        """#

        try withWorkspace { root in
            let compiled = try compile(source, root: root, mode: .jvmJar)
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
            let artifact = root.appendingPathComponent("hello.jar").path
            let runtime = try m11Runtime()

            _ = try jvmTool("kotlinc", ["-nowarn", "-include-runtime", "hello.kt", "-d", "reference.jar"], root: root)
            try javaSource.write(to: root.appendingPathComponent("Probe.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["Probe.java"], root: root)

            let referenceClasspath = root.path + ":" + root.appendingPathComponent("reference.jar").path + ":" + runtime
            let reference = try java(["-cp", referenceClasspath, "Probe"])
            let candidate = try java(["-cp", root.path + ":" + artifact + ":" + runtime, "Probe"])
            #expect(candidate.stdout == reference.stdout)
            #expect(candidate.stdout == """
            valueModifiers=true:true:true
            value=42
            mutableModifiers=true:true:false
            mutableBefore=7
            mutableAfter=9
            exposedModifiers=true:false:true
            exposed=11
            ordinaryModifiers=false:true
            ordinary=5
            """ + "\n")
            #expect(reference.stderr.isEmpty)
            #expect(candidate.stderr.isEmpty)
        }
    }

    @Test
    func rejectsJvmFieldOnPropertyWithoutBackingField() throws {
        let source = """
        object Obj {
            @JvmField val computed: Int get() = 42
        }
        fun main() {}
        """
        try withWorkspace { root in
            let compiled = try compile(source, root: root, mode: .jvmJar)
            #expect(compiled.0 == 1)
            #expect(compiled.1.contains { $0.severity == .error && $0.message.contains("backing field") })
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.jar").path))

            do {
                _ = try jvmTool("kotlinc", ["-nowarn", "hello.kt", "-d", "reference.jar"], root: root)
                Issue.record("kotlinc accepted @JvmField on a property without a backing field")
            } catch CommandRunnerError.nonZeroExit(let error) {
                #expect(error.exitCode != 0)
            }
        }
    }
}
#endif
