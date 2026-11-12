#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func accessorDeclarationAnnotationsReachJvmMethodsAndJavaConsumers() throws {
        try withWorkspace { root in
            let source = """
            @Retention(AnnotationRetention.RUNTIME)
            @Target(AnnotationTarget.PROPERTY_GETTER)
            annotation class GetterMark(val value: String)
            @Retention(AnnotationRetention.RUNTIME)
            @Target(AnnotationTarget.PROPERTY_SETTER)
            annotation class SetterMark(val value: String)

            class Box {
                val value: Int @GetterMark("declaration-getter") get() = 42
                var mutable: Int = 1
                @SetterMark("declaration-setter") set(v) { field = v }
                @get:GetterMark("use-site-getter") val explicitGet: Int = 43
                @set:SetterMark("use-site-setter") var explicitSet: Int = 1
            }

            fun main() {
                val box = Box()
                println(box.value)
                box.mutable = 42
                println(box.mutable)
                println(box.explicitGet)
                box.explicitSet = 44
                println(box.explicitSet)
            }
            """
            try runM11(source, expected: "42\n42\n43\n44\n", mode: .jvmJar, root: root)

            let runtime = try m11Runtime()
            let jar = root.appendingPathComponent("hello.jar").path
            try """
            public class AccessorConsumer {
                public static void main(String[] args) throws Exception {
                    java.lang.reflect.Method getter = Box.class.getDeclaredMethod("getValue");
                    java.lang.reflect.Method setter = Box.class.getDeclaredMethod("setMutable", int.class);
                    System.out.println(getter.getAnnotation(GetterMark.class).value());
                    System.out.println(java.util.Arrays.stream(Box.class.getDeclaredFields())
                        .anyMatch(field -> field.isAnnotationPresent(GetterMark.class)));
                    System.out.println(setter.getAnnotation(SetterMark.class).value());
                    System.out.println(Box.class.getDeclaredMethod("getMutable").isAnnotationPresent(SetterMark.class));
                    System.out.println(Box.class.getDeclaredMethod("getExplicitGet").getAnnotation(GetterMark.class).value());
                    System.out.println(Box.class.getDeclaredMethod("setExplicitSet", int.class).getAnnotation(SetterMark.class).value());
                    boolean hasPropertyCarrier;
                    try {
                        Box.class.getDeclaredMethod("getValue$annotations");
                        hasPropertyCarrier = true;
                    } catch (NoSuchMethodException expected) {
                        hasPropertyCarrier = false;
                    }
                    System.out.println(hasPropertyCarrier);
                    Box box = new Box();
                    setter.invoke(box, 99);
                    System.out.println(box.getMutable());
                }
            }
            """.write(to: root.appendingPathComponent("AccessorConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "AccessorConsumer.java"], root: root)

            let candidateClasspath = root.path + ":" + jar + ":" + runtime
            let consumer = try java(["-cp", candidateClasspath, "AccessorConsumer"])
            #expect(consumer.stdout == "declaration-getter\nfalse\ndeclaration-setter\nfalse\nuse-site-getter\nuse-site-setter\nfalse\n99\n")
            #expect(consumer.stderr.isEmpty)

            let reference = root.appendingPathComponent("reference.jar").path
            let referenceClasspath = root.path + ":" + reference + ":" + runtime
            let referenceConsumer = try java(["-cp", referenceClasspath, "AccessorConsumer"])
            #expect(referenceConsumer.stdout == consumer.stdout)
            #expect(referenceConsumer.stderr.isEmpty)
        }
    }

    @Test
    func accessorDeclarationAnnotationsUseAccessorTargetValidation() throws {
        try withWorkspace { root in
            let result = try compile("""
            @Target(AnnotationTarget.FUNCTION)
            annotation class FunctionOnly
            class Box {
                val value: Int @FunctionOnly get() = 42
            }
            """, root: root, mode: .jvmJar)

            #expect(result.0 != 0)
            #expect(result.1.contains { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }, "\(result.1.map(\.message))")
            #expect(!result.1.contains { $0.code == "KSWIFTK-JVM-0001" }, "\(result.1.map(\.message))")
        }
    }
}
#endif
