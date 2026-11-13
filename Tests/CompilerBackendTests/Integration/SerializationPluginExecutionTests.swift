import Testing

extension BundledStdlibExecutionTests {
    @Test func serializableClassSerializerEntryPoint() throws {
        try compileAndRunKotlin(
            serializationProgram(mainBody: "P.serializer(); println(\"created\")"),
            expectedOutput: "created\n"
        )
    }

    @Test func serializableClassDescriptor() throws {
        try compileAndRunKotlin(
            serializationProgram(mainBody: """
                val descriptor = P.serializer().descriptor
                println(descriptor.serialName)
                println(descriptor.elementsCount)
                """),
            expectedOutput: "P\n1\n"
        )
    }

    @Test func jsonFormatEncodesSerializableClass() throws {
        try compileAndRunKotlin(
            serializationProgram(mainBody: "println(Json.encodeToString(P(\"n\")))"),
            expectedOutput: "{\"name\":\"n\"}\n"
        )
    }

    @Test func jsonFormatDecodesSerializableClass() throws {
        try compileAndRunKotlin(
            serializationProgram(mainBody: #"println(Json.decodeFromString<P>("{\"name\":\"n\"}").name)"#),
            expectedOutput: "n\n"
        )
    }

    @Test func jsonElementRemainsReflectable() throws {
        try compileAndRunKotlin(
            serializationProgram(mainBody: "println(JsonElement::class.simpleName)"),
            expectedOutput: "JsonElement\n"
        )
    }
}

private func serializationProgram(mainBody: String) -> String {
    """
    import kotlinx.serialization.*
    import kotlinx.serialization.json.*

    @Serializable data class P(val name: String)

    fun main() {
        \(mainBody)
    }
    """
}
