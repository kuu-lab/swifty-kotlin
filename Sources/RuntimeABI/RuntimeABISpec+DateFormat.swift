private let abi = RuntimeABISectionBuilder("DateFormat")

public extension RuntimeABISpec {
    static let dateFormatFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_simple_date_format_parse", "patternRaw sourceRaw"),
        abi.nt("__kk_messageformat_datetime", "kind style millis locale"),
        abi.nt("__kk_simple_date_format_format", "pattern millis locale"),
    ]
}
