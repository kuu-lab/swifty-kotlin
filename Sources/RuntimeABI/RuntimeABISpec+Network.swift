private let abi = RuntimeABISectionBuilder("Network")

public extension RuntimeABISpec {
    static let networkFunctions: [RuntimeABIFunctionSpec] = [
        abi.th("kk_http_response_url", "responseRaw"),
        abi.th("kk_http_response_errorMessage", "responseRaw"),
        abi.th("kk_http_response_timedOut", "responseRaw"),
        abi.th("kk_http_response_isSuccessful", "responseRaw"),
        abi.th("kk_http_response_header", "responseRaw nameRaw"),
    ]
}
