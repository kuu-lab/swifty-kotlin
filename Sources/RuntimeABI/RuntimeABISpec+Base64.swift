public extension RuntimeABISpec {
    static let base64Functions: [RuntimeABIFunctionSpec] = [
        // KSP-482: encode/decode/padding logic moved to pure Kotlin
        // (Sources/CompilerCore/Stdlib/kotlin/io/encoding/Base64.kt). Only the
        // OutputStream.encodingWith stream wrapper stays as a runtime bridge.
        RuntimeABIFunctionSpec(
            name: "__kk_output_stream_encodingWith",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "alphabetRaw", type: .intptr),
                RuntimeABIParameter(name: "addPaddingRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Base64"
        ),
    ]
}
