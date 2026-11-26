#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

private let serializationRuntimeClasspath: [String] = {
    let value = ProcessInfo.processInfo.environment["KSWIFTK_JVM_SERIALIZATION_CLASSPATH"] ?? ""
    return value.split(separator: ":").map(String.init).filter { FileManager.default.fileExists(atPath: $0) }
}()

extension JVMBackendTests {
    @Test(.enabled(if: serializationRuntimeClasspath.count >= 3))
    func generatedSerializerRoundTripsThroughKotlinxJson() throws {
        try withWorkspace { root in
            let source = """
                import kotlinx.serialization.Serializable
                import kotlinx.serialization.SerialName
                import kotlinx.serialization.SerializationException
                import kotlinx.serialization.json.Json

                @Serializable
                class MediawikiData(var database: String? = null)

                @Serializable
                @SerialName("custom.Settings")
                class Settings(
                    val id: Long,
                    val label: String = "none",
                    @SerialName("on") val enabled: Boolean = true,
                    val ratio: Double = -1.5,
                    val limit: Int? = null,
                )

                @Serializable
                class Tagged(
                    @SerialName("value=on") val on: Boolean,
                    val label: String? = "local",
                    val count: Int? = 5,
                )

                fun main() {
                    println(Json.encodeToString(Tagged.serializer(), Tagged(true)))
                    println(Json.encodeToString(Tagged.serializer(), Tagged(false, null, 6)))
                    println(Json.encodeToString(Tagged.serializer(), Json.decodeFromString(Tagged.serializer(), "{\\"value=on\\":true}")))
                    println(Json.encodeToString(MediawikiData.serializer(), MediawikiData("enwiki")))
                    println(Json.encodeToString(MediawikiData.serializer(), MediawikiData()))
                    println(Json.decodeFromString(MediawikiData.serializer(), "{\\"database\\":\\"x\\"}").database)
                    println(Json.decodeFromString(MediawikiData.serializer(), "{}").database)
                    println(Json.encodeToString(Settings.serializer(), Settings(4L)))
                    println(Json.encodeToString(Settings.serializer(), Settings(4L, "a", false, 2.0, 7)))
                    val decoded = Json.decodeFromString(Settings.serializer(), "{\\"id\\":9,\\"limit\\":null}")
                    println("${decoded.id} ${decoded.label} ${decoded.enabled} ${decoded.ratio} ${decoded.limit}")
                    println(Settings.serializer().descriptor.serialName)
                    println(Settings.serializer().descriptor.isElementOptional(0))
                    println(Settings.serializer().descriptor.isElementOptional(1))
                    try {
                        Json.decodeFromString(Settings.serializer(), "{}")
                    } catch (e: SerializationException) {
                        println("missing field")
                    }
                }
                """
            let (exitCode, diagnostics) = try compile(source, root: root, mode: .jvmJar, classpath: serializationRuntimeClasspath)
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
            let classpath = ([root.appendingPathComponent("hello.jar").path] + serializationRuntimeClasspath).joined(separator: ":")
            let result = try java(["-cp", classpath, "HelloKt"])
            #expect(result.stdout == """
                {"value=on":true}
                {"value=on":false,"label":null,"count":6}
                {"value=on":true}
                {"database":"enwiki"}
                {}
                x
                null
                {"id":4}
                {"id":4,"label":"a","on":false,"ratio":2.0,"limit":7}
                9 none true -1.5 null
                custom.Settings
                false
                true
                missing field

                """)
        }
    }
}
#endif
