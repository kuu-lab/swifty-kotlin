private let abi = RuntimeABISectionBuilder("Base64")

public extension RuntimeABISpec {
    static let base64Functions: [RuntimeABIFunctionSpec] = [
        // KSP-482: encode/decode/padding logic moved to pure Kotlin
        // (Sources/CompilerCore/Stdlib/kotlin/io/encoding/Base64.kt). Only the
        // OutputStream.encodingWith stream wrapper stays as a runtime bridge.
        abi.th("__kk_output_stream_encodingWith", "streamRaw alphabetRaw addPaddingRaw"),
    ]
}
