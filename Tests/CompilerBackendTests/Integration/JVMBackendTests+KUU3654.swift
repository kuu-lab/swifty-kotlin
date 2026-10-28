#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu3654AnonymousAndLocalClassEnclosingMetadataMatchesReflection(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
            interface Action { fun run() }
            val topLevel: Action = object : Action { override fun run() {} }

            class Container {
                class Nested
                inner class Inner

                fun create(): Action = object : Action { override fun run() {} }

                fun createFromLocalFunction(): Action {
                    fun build(): Action = object : Action { override fun run() {} }
                    return build()
                }

                fun createLocalClass(): Any {
                    class Local
                    return Local()
                }
            }

            class ConstructorContainer {
                var created: Action? = null

                constructor(marker: Int) {
                    created = object : Action { override fun run() {} }
                }
            }
            """
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }

            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let consumer = """
            import java.util.Arrays;

            public class InspectEnclosingMetadata {
                public static void main(String[] args) {
                    System.out.println(Arrays.toString(Arrays.stream(Container.class.getDeclaredClasses())
                        .map(Class::getSimpleName).sorted().toArray()));
                    System.out.println(Container.Nested.class.getDeclaringClass() == Container.class);
                    System.out.println(Container.Inner.class.getDeclaringClass() == Container.class);

                    Class<?> anonymous = new Container().create().getClass();
                    System.out.println(anonymous.isAnonymousClass());
                    System.out.println(anonymous.getEnclosingClass() == Container.class);
                    System.out.println(anonymous.getDeclaringClass() == null);
                    System.out.println("create".equals(anonymous.getEnclosingMethod().getName()));

                    Class<?> topLevelAnonymous = HelloKt.getTopLevel().getClass();
                    System.out.println(topLevelAnonymous.isAnonymousClass());
                    System.out.println(topLevelAnonymous.getEnclosingClass() == HelloKt.class);
                    System.out.println(topLevelAnonymous.getEnclosingMethod() == null);
                    System.out.println(topLevelAnonymous.getEnclosingConstructor() == null);

                    Class<?> localFunctionAnonymous = new Container().createFromLocalFunction().getClass();
                    System.out.println(localFunctionAnonymous.isAnonymousClass());
                    System.out.println(localFunctionAnonymous.getEnclosingMethod() != null
                        && localFunctionAnonymous.getEnclosingMethod().getDeclaringClass() == Container.class);

                    Class<?> local = new Container().createLocalClass().getClass();
                    System.out.println(local.isLocalClass());
                    System.out.println(local.getEnclosingClass() == Container.class);

                    Class<?> constructorAnonymous = new ConstructorContainer(1).getCreated().getClass();
                    System.out.println(constructorAnonymous.isAnonymousClass());
                    System.out.println(constructorAnonymous.getEnclosingConstructor() != null
                        && constructorAnonymous.getEnclosingConstructor().getDeclaringClass() == ConstructorContainer.class);
                    System.out.println(constructorAnonymous.getEnclosingMethod() == null);
                }
            }
            """
            try consumer.write(
                to: root.appendingPathComponent("InspectEnclosingMetadata.java"),
                atomically: true,
                encoding: .utf8
            )
            _ = try jvmTool(
                "javac",
                ["-cp", output, "-d", root.path, "InspectEnclosingMetadata.java"],
                root: root
            )
            let execution = try java(["-cp", root.path + ":" + output, "InspectEnclosingMetadata"])
            #expect(execution.stdout == """
            [Inner, Nested]
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            """ + "\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
