import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func externalMemberExtensionPropertyReferencesRunWithRepositoryStdlib() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            import kotlin.reflect.KProperty
            import kotlin.reflect.KProperty2
            import kotlin.jvm.internal.PropertyReference2
            import kotlin.jvm.internal.PropertyReference2Impl
            import kotlin.jvm.internal.Reflection

            class Wrapper {
                val String.suffix: String by Delegate()
                fun read(value: String) = value.suffix
            }

            class Delegate {
                operator fun getValue(receiver: String, property: KProperty<*>): String =
                    receiver + ":" + property.name
            }

            fun main() {
                val wrapper = Wrapper()
                println(wrapper.read("receiver"))
                val reference: KProperty2<Any?, Any?, Any?> = Reflection.property2(
                    PropertyReference2Impl(Wrapper::class.java, "suffix", "getSuffix(Ljava/lang/String;)Ljava/lang/String;", 0)
                )
                println(reference.get(wrapper, "get"))
                println(reference.getter(wrapper, "getter"))
                println(reference(wrapper, "invoke"))
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.stdout == "receiver:suffix\nget:suffix\ngetter:suffix\ninvoke:suffix\n")
            #expect(result.stderr.isEmpty)
        }
    }
}
