// swiftlint:disable file_length

/// `RuntimeABISpec.systemFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {

    static let systemFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_system_exitProcess",
            parameters: [
                RuntimeABIParameter(name: "status", type: .intptr),
            ],
            returnType: .noreturn,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_currentTimeMillis",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_nanoTime",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_getTimeMicros",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_getTimeMillis",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_getTimeNanos",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_process_start_nanos",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_measureTimeMillis",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_measureTimeMicros",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_measureNanoTime",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_canAccessUnaligned",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_isLittleEndian",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_osFamily",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_cpuArchitecture",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_getAvailableProcessors",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_gc",
            parameters: [],
            returnType: .void,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_getRuntime",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_totalMemory",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_freeMemory",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_maxMemory",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_clock_now",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_clock_system_now",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_to_java_instant",
            parameters: [
                RuntimeABIParameter(name: "instantRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_to_js_date",
            parameters: [
                RuntimeABIParameter(name: "instantRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_js_date_to_kotlin_instant",
            parameters: [
                RuntimeABIParameter(name: "dateRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_js_array_toList",
            parameters: [
                RuntimeABIParameter(name: "jsArrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_js_bigint_toLong",
            parameters: [
                RuntimeABIParameter(name: "jsBigIntRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_js_reference_get",
            parameters: [
                RuntimeABIParameter(name: "jsRefRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_toJsReference",
            parameters: [
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_double_toJsNumber",
            parameters: [
                RuntimeABIParameter(name: "value", type: .double),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_js_map_toMap",
            parameters: [
                RuntimeABIParameter(name: "jsMapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_js_set_toMutableSet",
            parameters: [
                RuntimeABIParameter(name: "jsSetRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_js_set_toSet",
            parameters: [
                RuntimeABIParameter(name: "jsSetRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_js_number_toDouble",
            parameters: [
                RuntimeABIParameter(name: "jsNumberRaw", type: .intptr),
            ],
            returnType: .double,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_js_number_toInt",
            parameters: [
                RuntimeABIParameter(name: "jsNumberRaw", type: .intptr),
            ],
            returnType: .int32,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_toJsNumber",
            parameters: [
                RuntimeABIParameter(name: "value", type: .int32),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_js_boolean_toBoolean",
            parameters: [
                RuntimeABIParameter(name: "jsBooleanRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jsclass_kotlin",
            parameters: [
                RuntimeABIParameter(name: "jsClassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_toJsBigInt",
            parameters: [
                RuntimeABIParameter(name: "value", type: .int64),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dynamic_iterator",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_js_array_create",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_boolean_toJsBoolean",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toJsString",
            parameters: [
                RuntimeABIParameter(name: "stringRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
    ]
}
