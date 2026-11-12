#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func inlineJvmPropertyAccessorsMatchKotlincAndConsumers() throws {
        try withWorkspace { root in
            let source = """
            inline val String.doubledLength: Int get() = length * 2

            class Box {
                var raw = 0
                inline var value: Int
                    get() = raw
                    set(v) { raw = v }
            }

            class OrdinaryBox {
                var value: Int = 1
            }

            fun main() {
                println("abc".doubledLength)
                val box = Box()
                box.value = 7
                println(box.value)
                val ordinary = OrdinaryBox()
                ordinary.value = 9
                println(ordinary.value)
            }
            """
            let compilation = try compile(source, root: root, mode: .jvmJar)
            try #require(compilation.0 == 0, "\(compilation.1.map(\.message))")

            let runtime = try m11Runtime()
            let artifact = root.appendingPathComponent("hello.jar").path
            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            let reference = root.appendingPathComponent("reference.jar").path
            let generatedRun = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
            let referenceRun = try java(["-cp", reference + ":" + runtime, "HelloKt"])
            #expect(generatedRun.exitCode == 0)
            #expect(generatedRun.stderr.isEmpty)
            #expect(referenceRun.exitCode == 0)
            #expect(referenceRun.stderr.isEmpty)
            #expect(generatedRun.stdout == "6\n7\n9\n")
            #expect(generatedRun.stdout == referenceRun.stdout)

            try """
            public class JavaInlinePropertyConsumer {
                public static void main(String[] args) {
                    System.out.println(HelloKt.getDoubledLength("abcd"));
                    Box box = new Box();
                    box.setValue(11);
                    System.out.println(box.getValue());
                    OrdinaryBox ordinary = new OrdinaryBox();
                    ordinary.setValue(13);
                    System.out.println(ordinary.getValue());
                }
            }
            """.write(to: root.appendingPathComponent("JavaInlinePropertyConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", artifact + ":" + runtime, "JavaInlinePropertyConsumer.java"], root: root)
            let javaRun = try java(["-cp", root.path + ":" + artifact + ":" + runtime, "JavaInlinePropertyConsumer"])
            #expect(javaRun.exitCode == 0)
            #expect(javaRun.stderr.isEmpty)
            #expect(javaRun.stdout == "8\n11\n13\n")

            try """
            import kotlin.reflect.KMutableProperty1
            import kotlin.reflect.full.memberProperties

            fun main() {
                println("abcd".doubledLength)
                val box = Box()
                box.value = 17
                println(box.value)
                println(String::doubledLength.getter.isInline)
                val inlineValue = Box::class.memberProperties.single { it.name == "value" } as KMutableProperty1<Box, Int>
                println(inlineValue.getter.isInline)
                println(inlineValue.setter.isInline)
                val ordinaryValue = OrdinaryBox::class.memberProperties.single { it.name == "value" } as KMutableProperty1<OrdinaryBox, Int>
                println(ordinaryValue.getter.isInline)
                println(ordinaryValue.setter.isInline)
            }
            """.write(to: root.appendingPathComponent("KotlinInlinePropertyConsumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["KotlinInlinePropertyConsumer.kt", "-cp", artifact + ":" + runtime, "-d", "kotlin-consumer.jar"], root: root)
            let kotlinRun = try java(["-cp", root.appendingPathComponent("kotlin-consumer.jar").path + ":" + artifact + ":" + runtime, "KotlinInlinePropertyConsumerKt"])
            #expect(kotlinRun.exitCode == 0)
            #expect(kotlinRun.stderr.isEmpty)
            #expect(kotlinRun.stdout == "8\n17\ntrue\ntrue\ntrue\nfalse\nfalse\n")
        }
    }

    @Test
    func inlineJvmPropertiesContinueRejectingBackingFields() throws {
        let invalidSources = [
            "inline val initialized: Int = 1\nfun main() { println(initialized) }",
            "inline val explicitField: Int get() = field\nfun main() { println(explicitField) }",
        ]
        for source in invalidSources {
            try withWorkspace { root in
                let compilation = try compile(source, root: root, mode: .jvmJar)
                #expect(compilation.0 != 0, "KSwiftK accepted an inline property with a backing field.")
                #expect(!compilation.1.map(\.message).joined(separator: "\n").contains("Unsupported JVM property declaration"))

                let runtime = try m11Runtime()
                try source.write(to: root.appendingPathComponent("invalid.kt"), atomically: true, encoding: .utf8)
                do {
                    _ = try jvmTool("kotlinc", ["invalid.kt", "-cp", runtime, "-d", "invalid.jar"], root: root)
                    Issue.record("kotlinc accepted an inline property with a backing field.")
                } catch CommandRunnerError.nonZeroExit(let error) {
                    #expect(error.stderr.localizedCaseInsensitiveContains("inline property cannot have a backing field"))
                }
            }
        }
    }
}
#endif
