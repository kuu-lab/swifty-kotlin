private let abi = RuntimeABISectionBuilder("Base64")

public extension RuntimeABISpec {
    static let base64Functions: [RuntimeABIFunctionSpec] = [
        abi.th("__kk_output_stream_encodingWith", "streamRaw alphabetRaw addPaddingRaw"),
    ]
}
