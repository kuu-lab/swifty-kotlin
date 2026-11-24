#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    private func serializationStubClasspath(_ root: URL) throws -> String {
        let sources = [
            "kotlinx/serialization/KSerializer.java": "package kotlinx.serialization; public interface KSerializer<T> {}",
            "kotlinx/serialization/SerialName.java": """
            package kotlinx.serialization;
            import java.lang.annotation.*;
            @Retention(RetentionPolicy.RUNTIME)
            public @interface SerialName { String value(); }
            """,
            "kotlinx/serialization/Serializable.java": """
            package kotlinx.serialization;
            import java.lang.annotation.*;
            @Retention(RetentionPolicy.RUNTIME)
            public @interface Serializable { Class<? extends KSerializer> with() default KSerializer.class; }
            """,
        ]
        let classes = root.appendingPathComponent("serialization-stubs")
        try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)
        var paths: [String] = []
        for (name, contents) in sources.sorted(by: { $0.key < $1.key }) {
            let file = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file, atomically: true, encoding: .utf8)
            paths.append(name)
        }
        let result = try jvmTool("javac", ["--release", "8", "-d", "serialization-stubs"] + paths, root: root)
        try #require(result.exitCode == 0, "\(result.stderr)")
        return classes.path
    }

    private func jarEntries(_ root: URL, jar: String = "hello.jar") throws -> Set<String> {
        let result = try jvmTool("jar", ["tf", jar], root: root)
        try #require(result.exitCode == 0, "\(result.stderr)")
        return Set(result.stdout.split(separator: "\n").map(String.init))
    }

    private func members(_ root: URL, of name: String, jar: String = "hello.jar") throws -> String {
        let result = try jvmTool("javap", ["-p", "-cp", jar, name], root: root)
        try #require(result.exitCode == 0, "\(result.stderr)")
        return result.stdout
    }

    @Test
    func serializablePrimaryConstructorClassGetsGeneratedSerializerAndCompanion() throws {
        try withWorkspace { root in
            let stubs = try serializationStubClasspath(root)
            let source = """
                import kotlinx.serialization.Serializable

                @Serializable
                class Model(val name: String, var count: Int = 2, val tag: String? = null)

                fun main() { println("compiled") }
                """
            let (exitCode, diagnostics) = try compile(source, root: root, mode: .jvmJar, classpath: [stubs])
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
            let entries = try jarEntries(root)
            #expect(entries.contains("Model.class"))
            #expect(entries.contains("Model$Companion.class"))
            #expect(entries.contains("Model$$serializer.class"))

            let model = try members(root, of: "Model")
            #expect(model.contains("public static final Model$Companion Companion;"))
            #expect(model.contains("write$Self(Model, kotlinx.serialization.encoding.CompositeEncoder, kotlinx.serialization.descriptors.SerialDescriptor)"))

            let companion = try members(root, of: "Model$Companion")
            #expect(companion.contains("public final kotlinx.serialization.KSerializer<Model> serializer();"))

            let generated = try members(root, of: "Model$$serializer")
            #expect(generated.contains("implements kotlinx.serialization.internal.GeneratedSerializer<Model>"))
            #expect(generated.contains("public static final Model$$serializer INSTANCE;"))
            #expect(generated.contains("public final kotlinx.serialization.descriptors.SerialDescriptor getDescriptor();"))
            #expect(generated.contains("public final kotlinx.serialization.KSerializer<?>[] childSerializers();"))
            #expect(generated.contains("public final void serialize(kotlinx.serialization.encoding.Encoder, Model);"))
            #expect(generated.contains("public final Model deserialize(kotlinx.serialization.encoding.Decoder);"))
        }
    }

    @Test
    func generatedCompanionSerializerIsVisibleToSeparatelyCompiledConsumers() throws {
        try withWorkspace { modelRoot in
            let stubs = try serializationStubClasspath(modelRoot)
            let model = """
                package models

                import kotlinx.serialization.Serializable

                @Serializable
                class Model(var database: String? = null)
                """
            let (modelExit, modelDiagnostics) = try compile(model, root: modelRoot, mode: .jvmJar, classpath: [stubs])
            try #require(modelExit == 0, "\(modelDiagnostics.map(\.message))")
            let modelJar = modelRoot.appendingPathComponent("hello.jar")
            try withWorkspace { consumerRoot in
                let consumer = """
                    import kotlinx.serialization.KSerializer
                    import models.Model

                    fun pick(): KSerializer<Model> = Model.serializer()

                    fun main() { println("compiled") }
                    """
                let (exitCode, diagnostics) = try compile(consumer, root: consumerRoot, mode: .jvmJar, classpath: [stubs, modelJar.path])
                #expect(exitCode == 0, "\(diagnostics.map(\.message))")
            }
        }
    }

    @Test
    func serializableClassWithUserCompanionGetsSerializerFunction() throws {
        try withWorkspace { root in
            let stubs = try serializationStubClasspath(root)
            let source = """
                import kotlinx.serialization.Serializable

                @Serializable
                class Holder(val value: Int = 1) {
                    companion object {
                        val limit = 3
                    }
                }

                fun main() { println(Holder.limit) }
                """
            let (exitCode, diagnostics) = try compile(source, root: root, mode: .jvmJar, classpath: [stubs])
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
            #expect(try jarEntries(root).contains("Holder$$serializer.class"))
            let companion = try members(root, of: "Holder$Companion")
            #expect(companion.contains("serializer()"))
            #expect(companion.contains("getLimit()"))
        }
    }

    @Test
    func serializableClassWithThirtyOnePropertiesCompiles() throws {
        try withWorkspace { root in
            let stubs = try serializationStubClasspath(root)
            let parameters = (0..<31).map { "val p\($0): Int" }.joined(separator: ", ")
            let source = """
                import kotlinx.serialization.Serializable

                @Serializable
                class Wide(\(parameters))

                fun main() { println("compiled") }
                """
            let (exitCode, diagnostics) = try compile(source, root: root, mode: .jvmJar, classpath: [stubs])
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
            #expect(try jarEntries(root).contains("Wide$$serializer.class"))
        }
    }

    @Test
    func classSerialNamesKeepLiteralTextAndRejectEscapedNames() throws {
        try withWorkspace { root in
            let stubs = try serializationStubClasspath(root)
            let source = """
                import kotlinx.serialization.SerialName
                import kotlinx.serialization.Serializable

                @Serializable
                @SerialName("value=class")
                class Literal(val enabled: Boolean)

                @Serializable
                @SerialName("a\\nb")
                class Escaped(val x: Int)

                @Serializable
                @SerialName("a\\\\b")
                class Backslash(val x: Int)

                fun main() { println("compiled") }
                """
            let (exitCode, diagnostics) = try compile(source, root: root, mode: .jvmJar, classpath: [stubs])
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
            let entries = try jarEntries(root)
            #expect(entries.contains("Literal$$serializer.class"))
            #expect(!entries.contains("Escaped$$serializer.class"))
            #expect(!entries.contains("Backslash$$serializer.class"))
            let code = try jvmTool("javap", ["-p", "-c", "-constants", "-cp", "hello.jar", "Literal$$serializer"], root: root)
            try #require(code.exitCode == 0, "\(code.stderr)")
            #expect(code.stdout.contains("String value=class"))
        }
    }

    @Test
    func nullablePropertiesWithNonNullLiteralDefaultsGetGeneratedSerializer() throws {
        try withWorkspace { root in
            let stubs = try serializationStubClasspath(root)
            let source = """
                import kotlinx.serialization.Serializable

                @Serializable
                class Defaults(val label: String? = "local", val count: Int? = 5, val flag: Boolean? = null)

                fun main() { println("compiled") }
                """
            let (exitCode, diagnostics) = try compile(source, root: root, mode: .jvmJar, classpath: [stubs])
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
            #expect(try jarEntries(root).contains("Defaults$$serializer.class"))
        }
    }

    @Test
    func unsupportedSerializableShapesCompileWithoutGeneratedSerializer() throws {
        try withWorkspace { root in
            let stubs = try serializationStubClasspath(root)
            let source = """
                import kotlinx.serialization.Serializable

                @Serializable
                class Box<T>(val value: T)

                @Serializable
                class Names(val names: List<String>)

                @Serializable
                class Counter {
                    var count: Int = 0
                }

                @Serializable
                class Computed(val base: Int = 1 + 2)

                fun main() { println("compiled") }
                """
            let (exitCode, diagnostics) = try compile(source, root: root, mode: .jvmJar, classpath: [stubs])
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
            let entries = try jarEntries(root)
            #expect(entries.contains("Box.class"))
            #expect(entries.contains("Names.class"))
            #expect(entries.contains("Counter.class"))
            #expect(entries.contains("Computed.class"))
            #expect(!entries.contains { $0.contains("$$serializer") })
        }
    }
}
#endif
