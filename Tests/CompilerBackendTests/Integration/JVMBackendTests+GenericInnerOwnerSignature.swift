#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func genericInnerSignaturePreservesOwnerArguments(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
            class GenericOuter<T>(val value: T) {
                inner class Inner<U>(val other: U) {
                    inner class Deep<V>(val third: V)
                }
                class Static<W>(val value: W) {
                    inner class NestedInner<X>(val inner: X)
                }
            }
            class NonGenericOuter {
                inner class Inner<T>(val other: T)
            }
            interface OwnerSignatures {
                fun inner(): GenericOuter<String>.Inner<Int>
                fun nested(): GenericOuter.Static<String>
                fun deep(): GenericOuter<String>.Inner<Int>.Deep<Long>
                fun plain(): NonGenericOuter.Inner<String>
                fun boundary(): GenericOuter.Static<String>.NestedInner<Int>
                fun starred(): GenericOuter<*>.Inner<*>
            }
            """
            let result = try compile(source, root: root, mode: mode)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            try """
            public class GenericOwnerConsumer {
                static GenericOuter<String>.Inner<Integer> inner(OwnerSignatures value) { return value.inner(); }
                static GenericOuter.Static<String> nested(OwnerSignatures value) { return value.nested(); }
                static GenericOuter<String>.Inner<Integer>.Deep<Long> deep(OwnerSignatures value) { return value.deep(); }
                static NonGenericOuter.Inner<String> plain(OwnerSignatures value) { return value.plain(); }
                static GenericOuter.Static<String>.NestedInner<Integer> boundary(OwnerSignatures value) { return value.boundary(); }
                static GenericOuter<?>.Inner<?> starred(OwnerSignatures value) { return value.starred(); }
                public static void main(String[] args) throws Exception {
                    for (String name : new String[] {"inner", "nested", "deep", "plain", "boundary", "starred"})
                        System.out.println(name + "=" + OwnerSignatures.class.getMethod(name).getGenericReturnType().getTypeName());
                }
            }
            """.write(to: root.appendingPathComponent("GenericOwnerConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["hello.kt", "-include-runtime", "-d", "reference.jar"], root: root)
            let reference = root.appendingPathComponent("reference.jar").path
            var outputs: [String] = []
            for classpath in [reference, artifact] {
                _ = try jvmTool("javac", ["-cp", classpath, "GenericOwnerConsumer.java"], root: root)
                let execution = try java(["-cp", root.path + ":" + classpath, "GenericOwnerConsumer"])
                #expect(execution.exitCode == 0)
                #expect(execution.stderr.isEmpty)
                outputs.append(execution.stdout)
            }
            #expect(outputs[0] == outputs[1])
            #expect(outputs[0].contains("GenericOuter<java.lang.String>$Inner<java.lang.Integer>"))
        }
    }
}
#endif
