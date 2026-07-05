// swiftlint:disable file_length

/// `RuntimeABISpec.durationFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let durationFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_measureTime",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeMilliseconds",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeSeconds",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeMinutes",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeMicroseconds",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeNanoseconds",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeHours",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeDays",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toString",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toIsoString",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toComponents_seconds",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toComponents_minutes",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toComponents_hours",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toComponents_days",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_parse",
            parameters: [
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_parseOrNull",
            parameters: [
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_parseIsoString",
            parameters: [
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_parseIsoStringOrNull",
            parameters: [
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_zero",
            parameters: [],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_infinite",
            parameters: [],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_seconds",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_milliseconds",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_microseconds",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_nanoseconds",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_minutes",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_hours",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_days",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_seconds_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_milliseconds_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_microseconds_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_nanoseconds_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_minutes_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_hours_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_days_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_seconds_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_milliseconds_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_microseconds_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_nanoseconds_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_minutes_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_hours_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_days_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toDuration_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "unitOrdinal", type: .intptr),
            ],
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
            name: "kk_duration_toDuration_double",
            parameters: [
                RuntimeABIParameter(name: "valueBits", type: .intptr),
                RuntimeABIParameter(name: "unitOrdinal", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_absoluteValue",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
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
            name: "kk_duration_minus",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_compareTo",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_div_duration",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_to_java_duration",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_unit_to_time_unit",
            parameters: [
                RuntimeABIParameter(name: "unitOrdinal", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_unit_to_duration_unit",
            parameters: [
                RuntimeABIParameter(name: "timeUnitOrdinal", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_measureTimedValue",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_timedvalue_new",
            parameters: [
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_timedvalue_value",
            parameters: [
                RuntimeABIParameter(name: "timedValueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_timedvalue_duration",
            parameters: [
                RuntimeABIParameter(name: "timedValueRaw", type: .intptr),
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
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_elapsed_now",
            parameters: [
                RuntimeABIParameter(name: "markRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_has_passed_now",
            parameters: [
                RuntimeABIParameter(name: "markRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_has_not_passed_now",
            parameters: [
                RuntimeABIParameter(name: "markRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_plus_duration",
            parameters: [
                RuntimeABIParameter(name: "markRaw", type: .intptr),
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_minus_duration",
            parameters: [
                RuntimeABIParameter(name: "markRaw", type: .intptr),
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_minus_mark",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_compare",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
        // STDLIB-TIME-TYPE-009: TestTimeSource
        RuntimeABIFunctionSpec(
            name: "kk_test_time_source_new",
            parameters: [],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_time_source_plus_assign",
            parameters: [
                RuntimeABIParameter(name: "sourceRaw", type: .intptr),
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_time_source_mark_now",
            parameters: [
                RuntimeABIParameter(name: "sourceRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_time_source_read",
            parameters: [
                RuntimeABIParameter(name: "sourceRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration",
            isThrowing: false
        ),
    ]
}
