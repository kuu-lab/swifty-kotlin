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
        class CompanionHolder {
            companion object {
                @JvmField val exposed: Int = 13
                @JvmField var mutable: Int = 15
            }
        }
        class CollisionHolder {
            var x: Int = 1
            companion object {
                @JvmField var x: Int = 2
            }
        }
        class GenericCompanionHolder {
            companion object {
                @JvmField val values: List<String> = listOf("x")
            }
        }
        class PublicCollisionHolder {
            @JvmField var x: List<String> = listOf("a")
            companion object {
                @JvmField var x: Int = 2
            }
        }
        class PrivateConstantCollisionHolder {
            @JvmField var x: String = "a"
            companion object {
                private const val x: Int = 2
                fun read() = x
            }
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

                Class<?> companionHolderType = Class.forName("CompanionHolder");
                Field companionExposed = companionHolderType.getDeclaredField("exposed");
                int companionExposedModifiers = companionExposed.getModifiers();
                System.out.println("companionExposedModifiers=" + Modifier.isPublic(companionExposedModifiers) + ":" + Modifier.isStatic(companionExposedModifiers) + ":" + Modifier.isFinal(companionExposedModifiers));
                System.out.println("companionExposed=" + companionExposed.getInt(null));

                Field companionMutable = companionHolderType.getDeclaredField("mutable");
                int companionMutableModifiers = companionMutable.getModifiers();
                System.out.println("companionMutableModifiers=" + Modifier.isPublic(companionMutableModifiers) + ":" + Modifier.isStatic(companionMutableModifiers) + ":" + Modifier.isFinal(companionMutableModifiers));
                System.out.println("companionMutableBefore=" + companionMutable.getInt(null));
                companionMutable.setInt(null, 17);
                System.out.println("companionMutableAfter=" + companionMutable.getInt(null));

                Class<?> collisionType = Class.forName("CollisionHolder");
                Object collision = collisionType.getDeclaredConstructor().newInstance();
                Field collisionBacking = collisionType.getDeclaredField("x$1");
                collisionBacking.setAccessible(true);
                Field collisionExposed = collisionType.getDeclaredField("x");
                System.out.println("collisionBacking=" + collisionBacking.getInt(collision));
                System.out.println("collisionExposedStatic=" + Modifier.isStatic(collisionExposed.getModifiers()));
                System.out.println("collisionExposed=" + collisionExposed.getInt(null));

                Field values = Class.forName("GenericCompanionHolder").getDeclaredField("values");
                System.out.println("valuesGeneric=" + values.getGenericType().getTypeName());

                Class<?> publicCollisionType = Class.forName("PublicCollisionHolder");
                Object publicCollision = publicCollisionType.getDeclaredConstructor().newInstance();
                Field publicStatic = null;
                Field publicInstance = null;
                for (Field field : publicCollisionType.getDeclaredFields()) {
                    if (!field.getName().equals("x")) continue;
                    if (Modifier.isStatic(field.getModifiers())) publicStatic = field;
                    else publicInstance = field;
                }
                System.out.println("publicStaticType=" + publicStatic.getType().getName());
                System.out.println("publicStaticGeneric=" + publicStatic.getGenericType().getTypeName());
                System.out.println("publicStatic=" + publicStatic.getInt(null));
                System.out.println("publicInstanceType=" + publicInstance.getType().getName());
                System.out.println("publicInstanceGeneric=" + publicInstance.getGenericType().getTypeName());
                System.out.println("publicInstance=" + publicInstance.get(publicCollision));

                Class<?> privateConstantType = Class.forName("PrivateConstantCollisionHolder");
                Field privateConstant = privateConstantType.getDeclaredField("x$1");
                privateConstant.setAccessible(true);
                int privateConstantModifiers = privateConstant.getModifiers();
                System.out.println("privateConstantModifiers=" + Modifier.isPrivate(privateConstantModifiers) + ":" + Modifier.isStatic(privateConstantModifiers) + ":" + Modifier.isFinal(privateConstantModifiers));
                System.out.println("privateConstant=" + privateConstant.getInt(null));
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
            companionExposedModifiers=true:true:true
            companionExposed=13
            companionMutableModifiers=true:true:false
            companionMutableBefore=15
            companionMutableAfter=17
            collisionBacking=1
            collisionExposedStatic=true
            collisionExposed=2
            valuesGeneric=java.util.List<java.lang.String>
            publicStaticType=int
            publicStaticGeneric=int
            publicStatic=2
            publicInstanceType=java.util.List
            publicInstanceGeneric=java.util.List<java.lang.String>
            publicInstance=[a]
            privateConstantModifiers=true:true:true
            privateConstant=2
            """ + "\n")
            #expect(reference.stderr.isEmpty)
            #expect(candidate.stderr.isEmpty)
        }
    }

    @Test
    func rejectsEnumEntryCollisionWithRenamedBackingField() throws {
        let source = """
        enum class Holder {
            `x$1`;
            val x: Holder? = null
            companion object {
                @JvmField val x: Holder? = null
            }
        }
        fun main() {}
        """
        try withWorkspace { root in
            let compiled = try compile(source, root: root, mode: .jvmJar)
            #expect(compiled.0 == 1)
            #expect(compiled.1.contains { $0.severity == .error && $0.message.contains("platform declaration clash") })

            do {
                _ = try jvmTool("kotlinc", ["-nowarn", "hello.kt", "-d", "reference.jar"], root: root)
                Issue.record("kotlinc accepted an enum entry collision with a renamed backing field")
            } catch CommandRunnerError.nonZeroExit(let error) {
                #expect(error.exitCode != 0)
                #expect(error.stderr.contains("platform declaration clash"), "\(error.stderr)")
            }
        }
    }

    @Test
    func rejectsExposedJvmFieldPlatformClash() throws {
        let source = """
        class Holder {
            @JvmField var x: Int = 1
            companion object {
                @JvmField var x: Int = 2
            }
        }
        fun main() {}
        """
        try withWorkspace { root in
            let compiled = try compile(source, root: root, mode: .jvmJar)
            #expect(compiled.0 == 1)
            #expect(compiled.1.contains { $0.severity == .error && $0.message.contains("platform declaration clash") })

            do {
                _ = try jvmTool("kotlinc", ["-nowarn", "hello.kt", "-d", "reference.jar"], root: root)
                Issue.record("kotlinc accepted an exposed field platform clash")
            } catch CommandRunnerError.nonZeroExit(let error) {
                #expect(error.exitCode != 0)
                #expect(error.stderr.contains("platform declaration clash"), "\(error.stderr)")
            }
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
