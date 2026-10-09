// swiftlint:disable file_length

/// `RuntimeABISpec.durationFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let durationParseSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "kk_duration_parse",
        parameters: [
            RuntimeABIParameter(name: "valueRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Duration"
    )

    static let durationParseOrNullSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "kk_duration_parseOrNull",
        parameters: [
            RuntimeABIParameter(name: "valueRaw", type: .intptr),
        ],
        returnType: .intptr,
        section: "Duration",
        isThrowing: false
    )

    static let durationParseIsoStringSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "kk_duration_parseIsoString",
        parameters: [
            RuntimeABIParameter(name: "valueRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Duration"
    )

    static let durationParseIsoStringOrNullSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "kk_duration_parseIsoStringOrNull",
        parameters: [
            RuntimeABIParameter(name: "valueRaw", type: .intptr),
        ],
        returnType: .intptr,
        section: "Duration",
        isThrowing: false
    )

    static let durationFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeMilliseconds",
            parameters: [RuntimeABIParameter(name: "durationRaw", type: .intptr)],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeNanoseconds",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        durationParseSpec,
        durationParseOrNullSpec,
        durationParseIsoStringSpec,
        durationParseIsoStringOrNullSpec,
        RuntimeABIFunctionSpec(
            name: "kk_duration_zero",
            parameters: [],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toDuration_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "unitOrdinal", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_plus",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_source_mark_now",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_source_monotonic_mark_now",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
        // KSP-648: TimeMark operations live in kotlin/time/TimeMark.kt; only the
        // reading bridges remain native.
        RuntimeABIFunctionSpec(
            name: "__kk_time_mark_now_reading_nanos",
            parameters: [],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
        // KSP-649: TimeSource / Monotonic reading bridges and Clock factory.
        RuntimeABIFunctionSpec(
            name: "__kk_time_source_mark_now",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_time_source_monotonic_mark_now",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_time_source_as_clock",
            parameters: [
                RuntimeABIParameter(name: "sourceRaw", type: .intptr),
                RuntimeABIParameter(name: "originRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
    ]
}
