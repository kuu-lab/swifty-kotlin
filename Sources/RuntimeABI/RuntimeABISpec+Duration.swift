private let abi = RuntimeABISectionBuilder("Duration")

public extension RuntimeABISpec {
    static let durationParseSpec: RuntimeABIFunctionSpec = abi.th("kk_duration_parse", "valueRaw outThrown")
    static let durationParseOrNullSpec: RuntimeABIFunctionSpec = abi.nt("kk_duration_parseOrNull", "valueRaw")
    static let durationParseIsoStringSpec: RuntimeABIFunctionSpec = abi.th("kk_duration_parseIsoString", "valueRaw outThrown")
    static let durationParseIsoStringOrNullSpec: RuntimeABIFunctionSpec = abi.nt("kk_duration_parseIsoStringOrNull", "valueRaw")

    static let durationFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("kk_duration_inWholeMilliseconds", "durationRaw"),
        abi.th("kk_duration_inWholeNanoseconds", "durationRaw"),
        durationParseSpec,
        durationParseOrNullSpec,
        durationParseIsoStringSpec,
        durationParseIsoStringOrNullSpec,
        abi.th("kk_duration_zero"),
        abi.th("kk_duration_toDuration_long", "value unitOrdinal"),
        abi.th("kk_duration_plus", "lhsRaw rhsRaw"),
        abi.nt("kk_time_source_mark_now", "receiver"),
        abi.nt("kk_time_source_monotonic_mark_now", "receiver"),
        // KSP-648: TimeMark operations live in kotlin/time/TimeMark.kt; only the
        // reading bridges remain native.
        abi.nt("__kk_time_mark_now_reading_nanos"),
        abi.nt("__kk_time_source_mark_now", "receiver"),
        abi.nt("__kk_time_source_monotonic_mark_now", "receiver"),
        abi.nt("__kk_time_source_as_clock", "sourceRaw originRaw"),
    ]
}
