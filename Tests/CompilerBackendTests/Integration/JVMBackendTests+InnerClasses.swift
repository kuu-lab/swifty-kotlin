#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    func innerClassesSection(of className: String, root: URL, mode: EmitMode) throws -> String {
        let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
        let result = try jvmTool("javap", ["-v", "-classpath", artifact.path, className], root: root)
        #expect(result.exitCode == 0, "\(result.stderr)")
        let lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let header = lines.firstIndex(of: "InnerClasses:") else { return "" }
        return lines.dropFirst(header + 1).prefix { $0.hasPrefix(" ") }.joined(separator: "\n")
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func innerClassesMetadataIsScopedAndKeepsReflectionRelationships(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
            package metadata
            class Container {
                class Nested
                inner class Inner
                inner class Parent { inner class Deep }
            }
            class DescriptorDecoy(val value: Container.Nested?)
            class DeepDescriptorDecoy(val value: Container.Parent.Deep?)
            class SignatureDecoy<T : Container.Nested>
            class GenericOuter<T> { inner class Inner<U> }
            class GenericSignatureDecoy<T : GenericOuter<String>.Inner<Int>>
            class Unrelated
            interface Action { fun run() }
            fun anonymous() = object : Action { override fun run() {} }
            fun main() {
                val nested = Container.Nested()
                val inner = Container().Inner()
                val parent = Container().Parent()
                val deep = parent.Deep()
                DescriptorDecoy(nested)
                DeepDescriptorDecoy(deep)
                val generic: SignatureDecoy<Container.Nested> = SignatureDecoy()
                anonymous().run()
                println("ok")
            }
            """
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }

            let container = try innerClassesSection(of: "metadata.Container", root: root, mode: mode)
            #expect(container.contains("metadata/Container$Nested"))
            #expect(container.contains("metadata/Container$Inner"))
            #expect(container.contains("metadata/Container$Parent"))
            #expect(!container.contains("metadata/Container$Parent$Deep"))

            let descriptorDecoy = try innerClassesSection(of: "metadata.DescriptorDecoy", root: root, mode: mode)
            #expect(descriptorDecoy.contains("metadata/Container$Nested"))
            #expect(!descriptorDecoy.contains("metadata/Container$Inner"))
            #expect(!descriptorDecoy.contains("metadata/Container$Parent"))

            let deepDescriptorDecoy = try innerClassesSection(of: "metadata.DeepDescriptorDecoy", root: root, mode: mode)
            #expect(deepDescriptorDecoy.contains("metadata/Container$Parent$Deep"))
            #expect(deepDescriptorDecoy.contains("metadata/Container$Parent"))
            #expect(!deepDescriptorDecoy.contains("metadata/Container$Nested"))

            let signatureDecoy = try innerClassesSection(of: "metadata.SignatureDecoy", root: root, mode: mode)
            #expect(signatureDecoy.contains("metadata/Container$Nested"))
            let genericSignatureDecoy = try innerClassesSection(of: "metadata.GenericSignatureDecoy", root: root, mode: mode)
            #expect(genericSignatureDecoy.contains("metadata/GenericOuter$Inner"))
            #expect(genericSignatureDecoy.contains("metadata/GenericOuter"))
            #expect(!genericSignatureDecoy.contains("metadata/Container$"))
            #expect(try innerClassesSection(of: "metadata.Unrelated", root: root, mode: mode).isEmpty)

            let facade = try innerClassesSection(of: "metadata.HelloKt", root: root, mode: mode)
            #expect(facade.contains("metadata/Container$Nested"))
            #expect(facade.contains("metadata/Container$Inner"))
            #expect(facade.contains("metadata/Container$Parent$Deep"))
            #expect(facade.contains("class metadata/HelloKt$anonymous$1"))

            try """
            import java.util.Arrays;
            import java.util.stream.Collectors;
            import metadata.Container;
            import metadata.DescriptorDecoy;
            import metadata.Unrelated;
            public class MetadataConsumer {
                public static void main(String[] args) {
                    String names = Arrays.stream(Container.class.getDeclaredClasses())
                        .map(Class::getSimpleName).sorted().collect(Collectors.joining(","));
                    System.out.println(names);
                    System.out.println(Container.Inner.class.getDeclaringClass() == Container.class);
                    System.out.println(Container.Parent.Deep.class.getDeclaringClass() == Container.Parent.class);
                    System.out.println(DescriptorDecoy.class.getDeclaredClasses().length);
                    System.out.println(Unrelated.class.getDeclaredClasses().length);
                }
            }
            """.write(to: root.appendingPathComponent("MetadataConsumer.java"), atomically: true, encoding: .utf8)

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            _ = try jvmTool("javac", ["-classpath", artifact.path, "-d", root.path, "MetadataConsumer.java"], root: root)
            let classpath = root.path + ":" + artifact.path
            let consumer = try java(["-classpath", classpath, "MetadataConsumer"])
            #expect(consumer.stdout == "Inner,Nested,Parent\ntrue\ntrue\n0\n0\n")
            #expect(consumer.stderr.isEmpty)
            let execution = try java(["-classpath", classpath, "metadata.HelloKt"])
            #expect(execution.stdout == "ok\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
