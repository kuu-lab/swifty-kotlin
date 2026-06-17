// swiftlint:disable file_length
public enum RuntimeABICType: String, Equatable, Sendable {
    case void
    case uint32 = "uint32_t"
    case uint64 = "uint64_t"
    case int32 = "int32_t"
    case intptr = "intptr_t"
    case opaquePointer = "void *"
    case nullableOpaquePointer = "void * _Nullable"
    case constUInt8Pointer = "const uint8_t *"
    case constCCharPointer = "const char *"
    case fieldAddrPointer = "void **"
    case constTypeInfoPointer = "const KTypeInfo *"
    case nullableRawPointerPointer = "void ** _Nullable"
    case int64 = "int64_t"
    case constRawPointer = "const void *"
    case nullableConstRawPointer = "const void * _Nullable"
    case nullableIntptrPointer = "intptr_t * _Nullable"
    case float = "float"
    case double = "double"
    case noreturn = "_Noreturn void"
}

public struct RuntimeABIParameter: Equatable, Sendable {
    public let name: String
    public let type: RuntimeABICType

    public init(name: String, type: RuntimeABICType) {
        self.name = name
        self.type = type
    }
}

public struct RuntimeABIFunctionSpec: Equatable, Sendable {
    public let name: String
    public let parameters: [RuntimeABIParameter]
    public let returnType: RuntimeABICType
    public let section: String
    /// Whether the runtime callee may throw (Kotlin exception propagation via `outThrown`).
    /// Defaults to `true`; non-throwing callees omit the `outThrown` ABI lowering path.
    public let isThrowing: Bool

    public init(
        name: String,
        parameters: [RuntimeABIParameter],
        returnType: RuntimeABICType,
        section: String,
        isThrowing: Bool = true
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.section = section
        self.isThrowing = isThrowing
    }

    public var cDeclaration: String {
        let params: String = if parameters.isEmpty {
            "void"
        } else {
            parameters.map { "\($0.type.rawValue) \($0.name)" }.joined(separator: ", ")
        }
        return "\(returnType.rawValue) \(name)(\(params));"
    }

    /// Parameter types only (no names), for ABI reconciliation with `RuntimeABIExterns`.
    public var parameterTypeStrings: [String] {
        parameters.map(\.type.rawValue)
    }

    /// Return type as a raw C string, for ABI reconciliation.
    public var returnTypeString: String {
        returnType.rawValue
    }
}

// swiftlint:disable:next type_body_length
public enum RuntimeABISpec {
    public static let specVersion = "J33"



    public static let memoryFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_alloc",
            parameters: [
                RuntimeABIParameter(name: "size", type: .uint32),
                RuntimeABIParameter(name: "typeInfo", type: .constTypeInfoPointer),
            ],
            returnType: .opaquePointer,
            section: "Memory"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_gc_collect",
            parameters: [],
            returnType: .void,
            section: "Memory",
            isThrowing: false,
        ),
    ]


    public static let testFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_test_assertEquals",
            parameters: [
                RuntimeABIParameter(name: "expected", type: .intptr),
                RuntimeABIParameter(name: "actual", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_assertEquals_message",
            parameters: [
                RuntimeABIParameter(name: "expected", type: .intptr),
                RuntimeABIParameter(name: "actual", type: .intptr),
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_assertTrue",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_assertTrue_message",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_assertNull",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_assertNull_message",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
    ]


    public static let consolePrintFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_print_any",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "Print",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_println_any",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "Print",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_println_bool",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .void,
            section: "Print"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_println_ulong",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .void,
            section: "Print",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_print_noarg",
            parameters: [],
            returnType: .void,
            section: "Print",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_println_newline",
            parameters: [],
            returnType: .void,
            section: "Print",
            isThrowing: false,
        ),
    ]


    public static let ioFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_io_default_buffer_size",
            parameters: [],
            returnType: .intptr,
            section: "IO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_readline",
            parameters: [],
            returnType: .intptr,
            section: "IO",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_readln",
            parameters: [
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "IO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_readlnOrNull",
            parameters: [],
            returnType: .intptr,
            section: "IO",
            isThrowing: false,
        ),
    ]


    public static let systemFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_system_exitProcess",
            parameters: [
                RuntimeABIParameter(name: "status", type: .intptr),
            ],
            returnType: .noreturn,
            section: "System",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_currentTimeMillis",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_nanoTime",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_getTimeMicros",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_getTimeMillis",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_getTimeNanos",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_process_start_nanos",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
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
            section: "System",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_isLittleEndian",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_osFamily",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_cpuArchitecture",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_getAvailableProcessors",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_gc",
            parameters: [],
            returnType: .void,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_getRuntime",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_totalMemory",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_freeMemory",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_maxMemory",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_clock_now",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "System",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_clock_system_now",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
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
            section: "System",
            isThrowing: false
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
            name: "kk_boolean_toJsBoolean",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
    ]


    public static let gcFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_register_global_root",
            parameters: [
                RuntimeABIParameter(name: "slot", type: .nullableRawPointerPointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unregister_global_root",
            parameters: [
                RuntimeABIParameter(name: "slot", type: .nullableRawPointerPointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_register_frame_map",
            parameters: [
                RuntimeABIParameter(name: "functionID", type: .uint32),
                RuntimeABIParameter(name: "mapPtr", type: .nullableConstRawPointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_push_frame",
            parameters: [
                RuntimeABIParameter(name: "functionID", type: .uint32),
                RuntimeABIParameter(name: "frameBase", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_pop_frame",
            parameters: [],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_register_coroutine_root",
            parameters: [
                RuntimeABIParameter(name: "value", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unregister_coroutine_root",
            parameters: [
                RuntimeABIParameter(name: "value", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_heap_object_count",
            parameters: [],
            returnType: .uint32,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_force_reset",
            parameters: [],
            returnType: .void,
            section: "GC"
        ),
    ]


    public static let boxingFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_box_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_box_bool",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_lateinit_is_initialized",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_lateinit_get_or_throw",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "propertyName", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_int",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_bool",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_box_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_box_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_box_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_box_char",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_long",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_float",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_double",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_char",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
    ]


    public static let arrayFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_array_new",
            parameters: [
                RuntimeABIParameter(name: "length", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_of_nulls",
            parameters: [
                RuntimeABIParameter(name: "length", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_new",
            parameters: [
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "classId", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_type_id",
            parameters: [
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_get",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Array"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_get_inbounds",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_set",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Array"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_binarySearch_compare",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "fromIndex", type: .intptr),
                RuntimeABIParameter(name: "toIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Array"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_vararg_spread_concat",
            parameters: [
                RuntimeABIParameter(name: "pairsArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "pairCount", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array",
            isThrowing: false
        ),
    ]


    /// Stdlib Delegate Functions (P5-80)

    /// Stdlib Delegate Functions (P5-80)
    public static let delegateFunctions: [RuntimeABIFunctionSpec] = [
        // Lazy
        RuntimeABIFunctionSpec(
            name: "kk_lazy_create",
            parameters: [
                RuntimeABIParameter(name: "initFnPtr", type: .intptr),
                RuntimeABIParameter(name: "mode", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_lazy_of",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_lazy_get_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_lazy_is_initialized",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        // Observable
        RuntimeABIFunctionSpec(
            name: "kk_observable_create",
            parameters: [
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "callbackFnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_observable_get_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_observable_set_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "newValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        // Vetoable
        RuntimeABIFunctionSpec(
            name: "kk_vetoable_create",
            parameters: [
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "callbackFnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_vetoable_get_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_vetoable_set_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "newValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        // NotNull
        RuntimeABIFunctionSpec(
            name: "kk_notNull_create",
            parameters: [],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_notNull_get_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_notNull_set_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "newValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_custom_delegate_create",
            parameters: [
                RuntimeABIParameter(name: "delegateHandle", type: .intptr),
                RuntimeABIParameter(name: "getValueFnPtr", type: .intptr),
                RuntimeABIParameter(name: "setValueFnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_custom_delegate_get_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "thisRef", type: .intptr),
                RuntimeABIParameter(name: "property", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_custom_delegate_set_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "thisRef", type: .intptr),
                RuntimeABIParameter(name: "property", type: .intptr),
                RuntimeABIParameter(name: "newValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_delegate_get_value",
            parameters: [
                RuntimeABIParameter(name: "delegateRaw", type: .intptr),
                RuntimeABIParameter(name: "thisRef", type: .intptr),
                RuntimeABIParameter(name: "property", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_delegate_set_value",
            parameters: [
                RuntimeABIParameter(name: "delegateRaw", type: .intptr),
                RuntimeABIParameter(name: "thisRef", type: .intptr),
                RuntimeABIParameter(name: "property", type: .intptr),
                RuntimeABIParameter(name: "newValue", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_function_invoke",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "arg", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_function_invoke_0",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_suspend_function_invoke",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "arg", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_suspend_function_invoke_0",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_function_invoke_2",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "arg1", type: .intptr),
                RuntimeABIParameter(name: "arg2", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_function_invoke_3",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "arg1", type: .intptr),
                RuntimeABIParameter(name: "arg2", type: .intptr),
                RuntimeABIParameter(name: "arg3", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_function_create_0",
            parameters: [
                RuntimeABIParameter(name: "bodyRaw", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_function_create_1",
            parameters: [
                RuntimeABIParameter(name: "bodyRaw", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_function_create_2",
            parameters: [
                RuntimeABIParameter(name: "bodyRaw", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
    ]
    /// Boolean logical operators

    /// Boolean logical operators
    public static let booleanFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_op_not",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boolean",
            isThrowing: false
        ),
    ]

    /// Char operations

    /// Char operations
    public static let charFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_char_minus",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Char"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_rangeTo",
            parameters: [
                RuntimeABIParameter(name: "startValue", type: .intptr),
                RuntimeABIParameter(name: "endValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Char"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_compareTo",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Char",
            isThrowing: false
        ),
    ]

    /// Regex (STDLIB-100/101/102/103)

    /// Regex (STDLIB-100/101/102/103)
    public static let regexFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_regex_create",
            parameters: [
                RuntimeABIParameter(name: "pattern", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_matches_regex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_contains_regex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_regex_find",
            parameters: [
                RuntimeABIParameter(name: "regex", type: .intptr),
                RuntimeABIParameter(name: "input", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_regex_findAll",
            parameters: [
                RuntimeABIParameter(name: "regex", type: .intptr),
                RuntimeABIParameter(name: "input", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replace_regex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
                RuntimeABIParameter(name: "replacement", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_split_regex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toRegex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-TEXT-FN-105: String.toRegex(option) / String.toRegex(options)
        RuntimeABIFunctionSpec(
            name: "kk_string_toRegex_with_option",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "option", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toRegex_with_options",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "options", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_regex_pattern",
            parameters: [
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-REGEX-096: Regex.options: Set<RegexOption>
        RuntimeABIFunctionSpec(
            name: "kk_regex_options",
            parameters: [
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_result_value",
            parameters: [
                RuntimeABIParameter(name: "matchResult", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_result_groupValues",
            parameters: [
                RuntimeABIParameter(name: "matchResult", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-351: Regex.replace lambda / STDLIB-350: Regex.matchEntire
        RuntimeABIFunctionSpec(
            name: "kk_regex_replace_lambda",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_regex_matchEntire",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-480: Regex(pattern, option) constructor
        RuntimeABIFunctionSpec(
            name: "kk_regex_create_with_option",
            parameters: [
                RuntimeABIParameter(name: "patternRaw", type: .intptr),
                RuntimeABIParameter(name: "optionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-480: Regex(pattern, options: Set<RegexOption>) constructor
        RuntimeABIFunctionSpec(
            name: "kk_regex_create_with_options",
            parameters: [
                RuntimeABIParameter(name: "patternRaw", type: .intptr),
                RuntimeABIParameter(name: "optionsSetRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-480: Regex.containsMatchIn(input)
        RuntimeABIFunctionSpec(
            name: "kk_regex_containsMatchIn",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "inputRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // MatchResult.groups / MatchGroupCollection / MatchGroup
        RuntimeABIFunctionSpec(
            name: "kk_match_result_groups",
            parameters: [
                RuntimeABIParameter(name: "matchRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_group_collection_get",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_group_collection_get_at",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_group_collection_size",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_group_value",
            parameters: [
                RuntimeABIParameter(name: "groupRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_group_range",
            parameters: [
                RuntimeABIParameter(name: "groupRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-REGEX-094: Regex.matches(input)
        // STDLIB-REGEX-094: Regex.fromLiteral
        // First param is the Companion object receiver (ignored at runtime).
        RuntimeABIFunctionSpec(
            name: "kk_regex_from_literal",
            parameters: [
                RuntimeABIParameter(name: "companionRef", type: .intptr),
                RuntimeABIParameter(name: "literalRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // STDLIB-REGEX-094: String.replaceFirst(Regex, replacement)
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceFirst_regex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
                RuntimeABIParameter(name: "replacement", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // STDLIB-REGEX-097: Regex.groupNames
        RuntimeABIFunctionSpec(
            name: "kk_regex_group_names",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_chunked",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_chunked_sequence",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_chunked_sequence_transform",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_windowed_default",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_windowed",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_windowed_partial",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_windowedSequence_partial",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_windowedSequence_transform",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-318: commonPrefixWith / commonSuffixWith
        RuntimeABIFunctionSpec(
            name: "kk_string_commonPrefixWith",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "other", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_commonSuffixWith",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "other", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-575/576: commonPrefixWith / commonSuffixWith (ignoreCase overloads)
        RuntimeABIFunctionSpec(
            name: "kk_string_commonPrefixWith_ignoreCase",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "other", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_commonSuffixWith_ignoreCase",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "other", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-316: String.zipWithNext()
        RuntimeABIFunctionSpec(
            name: "kk_string_zipWithNext",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-316: String.zipWithNext(transform: (Char, Char) -> R)
        RuntimeABIFunctionSpec(
            name: "kk_string_zipWithNextTransform",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-317: String.asSequence / asIterable
        RuntimeABIFunctionSpec(
            name: "kk_string_asSequence",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
    ]


    public static let i18nFunctions: [RuntimeABIFunctionSpec] = []

    // MARK: - Path (STDLIB-IO-089)


    // MARK: - Path (STDLIB-IO-089)

    public static let pathFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(name: "kk_path_new", parameters: [RuntimeABIParameter(name: "pathStringRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_name", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_invariantSeparatorsPath", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_invariantSeparatorsPathString", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_pathString", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_fileName", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_nameWithoutExtension", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_extension", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_parent", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_root", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_nameCount", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_toString", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_resolve_string", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_resolve_path", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_relativize", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_normalize", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_exists", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_isDirectory", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_isRegularFile", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_isAbsolute", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_readText", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_writeText", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "textRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_appendText_default", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "textRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_appendText", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "textRaw", type: .intptr), RuntimeABIParameter(name: "charsetRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_copyTo_options", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "targetRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_copyTo_overwrite", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "targetRaw", type: .intptr), RuntimeABIParameter(name: "overwriteRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_appendLines_iterable_default", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "linesRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_appendLines_iterable", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "linesRaw", type: .intptr), RuntimeABIParameter(name: "charsetRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_appendLines_sequence_default", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "linesRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_appendLines_sequence", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "linesRaw", type: .intptr), RuntimeABIParameter(name: "charsetRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_appendBytes", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "arrayRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_readLines", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_bufferedReader", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "charsetRaw", type: .intptr), RuntimeABIParameter(name: "bufferSizeRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_bufferedWriter", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "charsetRaw", type: .intptr), RuntimeABIParameter(name: "bufferSizeRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_createDirectories", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_createDirectories_attributes", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "attributesRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_createDirectory_attributes", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "attributesRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_createFile_attributes", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "attributesRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_createParentDirectories_attributes", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "attributesRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_createTempDirectory_directory_prefix_attributes", parameters: [RuntimeABIParameter(name: "directoryRaw", type: .intptr), RuntimeABIParameter(name: "prefixRaw", type: .intptr), RuntimeABIParameter(name: "attributesRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_createTempDirectory_prefix_attributes", parameters: [RuntimeABIParameter(name: "prefixRaw", type: .intptr), RuntimeABIParameter(name: "attributesRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_deleteIfExists", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_listDirectoryEntries", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_startsWith_path", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_startsWith_string", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_endsWith_path", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_endsWith_string", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_toFile", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_toUri", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_get", parameters: [RuntimeABIParameter(name: "pathStringRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_toAbsolutePath", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_toAbsolutePathString", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_getName", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "indexRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_relativeToOrSelf", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "baseRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_relativeTo", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "baseRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_relativeToOrNull", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "baseRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_readSymbolicLink", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_fileStore", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_isExecutable", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_isHidden", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_isReadable", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_isSymbolicLink", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_isWritable", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_isSameFileAs", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_fileSize", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_uri_toPath", parameters: [RuntimeABIParameter(name: "uriRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_readBytes", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_readLines_charset", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "charsetRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_readText_charset", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "charsetRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_writeBytes", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "arrayRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_createLinkPointingTo", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "targetRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_createSymbolicLinkPointingTo_attributes", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "targetRaw", type: .intptr), RuntimeABIParameter(name: "attributesRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_createTempFile_directory_prefix_suffix_attributes", parameters: [RuntimeABIParameter(name: "directoryRaw", type: .intptr), RuntimeABIParameter(name: "prefixRaw", type: .intptr), RuntimeABIParameter(name: "suffixRaw", type: .intptr), RuntimeABIParameter(name: "attributesRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_createTempFile_prefix_suffix_attributes", parameters: [RuntimeABIParameter(name: "prefixRaw", type: .intptr), RuntimeABIParameter(name: "suffixRaw", type: .intptr), RuntimeABIParameter(name: "attributesRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_deleteExisting", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_setOwner", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "ownerRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_setPosixFilePermissions", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "permissionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_deleteRecursively", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_copyToRecursively_overwrite", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "targetRaw", type: .intptr), RuntimeABIParameter(name: "onErrorRaw", type: .intptr), RuntimeABIParameter(name: "followLinksRaw", type: .intptr), RuntimeABIParameter(name: "overwriteRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_copyToRecursively_copyAction", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "targetRaw", type: .intptr), RuntimeABIParameter(name: "onErrorRaw", type: .intptr), RuntimeABIParameter(name: "followLinksRaw", type: .intptr), RuntimeABIParameter(name: "copyActionRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_div_path", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_div_string", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_useLines", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "charsetRaw", type: .intptr), RuntimeABIParameter(name: "fnPtr", type: .intptr), RuntimeABIParameter(name: "closureRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_useLines_default", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "fnPtr", type: .intptr), RuntimeABIParameter(name: "closureRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_visitFileTree", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "visitorRaw", type: .intptr), RuntimeABIParameter(name: "maxDepthRaw", type: .intptr), RuntimeABIParameter(name: "followLinksRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_visitFileTree_builder", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "maxDepthRaw", type: .intptr), RuntimeABIParameter(name: "followLinksRaw", type: .intptr), RuntimeABIParameter(name: "builderActionRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_walk", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_writeLines_iterable", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "linesRaw", type: .intptr), RuntimeABIParameter(name: "charsetRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_setAttribute", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "attributeRaw", type: .intptr), RuntimeABIParameter(name: "valueRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_useDirectoryEntries", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "globRaw", type: .intptr), RuntimeABIParameter(name: "actionRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_useDirectoryEntries_default", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "actionRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_writeLines_sequence", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "linesRaw", type: .intptr), RuntimeABIParameter(name: "charsetRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_fileAttributesViewOrNull", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_forEachDirectoryEntry", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "globRaw", type: .intptr), RuntimeABIParameter(name: "actionRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_forEachDirectoryEntry_default", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "actionRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_get_base_subpaths", parameters: [RuntimeABIParameter(name: "baseRaw", type: .intptr), RuntimeABIParameter(name: "subpathsRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_writer", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "charsetRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_forEachLine", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "charsetRaw", type: .intptr), RuntimeABIParameter(name: "actionRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_forEachLine_default", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "actionRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_readAttributes_string", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "attributesRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_readAttributes", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_writeText_options", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "textRaw", type: .intptr), RuntimeABIParameter(name: "charsetRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_reader", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "charsetRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_reader_default", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_moveTo_overwrite", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "targetRaw", type: .intptr), RuntimeABIParameter(name: "overwriteRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_fileVisitor", parameters: [RuntimeABIParameter(name: "builderActionRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_getPosixFilePermissions", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_notExists", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_outputStream", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_inputStream", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_getAttribute", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "attributeRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_fileAttributesView", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "typeRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_getOwner", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_moveTo_options", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "targetRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_getLastModifiedTime", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "optionsRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
    ]

    // MARK: - Duration / measureTime (STDLIB-230/231)


    // MARK: - Duration / measureTime (STDLIB-230/231)

    public static let durationFunctions: [RuntimeABIFunctionSpec] = [
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

    /// Concatenation of every sub-array of `RuntimeABIFunctionSpec` defined in this module.
    ///
    /// The sub-arrays are listed in alphabetical order, one entry per line, so that
    /// parallel branches adding a new category insert their entry at a unique
    /// alphabetic position rather than all appending to the same trailing line.
    /// This is purely a merge-conflict-prevention layout: the resulting element
    /// set is unchanged from any other ordering.
    ///
    /// When adding a new sub-array, insert its name in alphabetical position.
    /// Do NOT append at the end — that re-introduces the trailing-line conflict pattern.


    /// Concatenation of every sub-array of `RuntimeABIFunctionSpec` defined in this module.
    ///
    /// The sub-arrays are listed in alphabetical order, one entry per line, so that
    /// parallel branches adding a new category insert their entry at a unique
    /// alphabetic position rather than all appending to the same trailing line.
    /// This is purely a merge-conflict-prevention layout: the resulting element
    /// set is unchanged from any other ordering.
    ///
    /// When adding a new sub-array, insert its name in alphabetical position.
    /// Do NOT append at the end — that re-introduces the trailing-line conflict pattern.
    public static let allFunctions: [RuntimeABIFunctionSpec] = ([
        abiParityFunctions,
        arrayFunctions,
        atomicFunctions,
        base64Functions,
        bigIntegerFunctions,
        bitwiseFunctions,
        booleanFunctions,
        boxingFunctions,
        callableRefFunctions,
        charFunctions,
        collectionBridgeFunctions,
        collectionFunctions,
        comparatorFunctions,
        consolePrintFunctions,
        coroutineFunctions,
        deepRecursiveFunctions,
        delegateFunctions,
        dispatchBridgeFunctions,
        durationFunctions,
        exceptionFunctions,
        fileIOFunctions,
        gcFunctions,
        hexFormatFunctions,
        i18nFunctions,
        ioFunctions,
        kFunctionFunctions,
        kParameterFunctions,
        kPropertyStubFunctions,
        kotlinVersionFunctions,
        mathFunctions,
        memoryFunctions,
        nativeRefFunctions,
        networkFunctions,
        numericRuntimeBridgeFunctions,
        operatorFunctions,
        parallelFunctions,
        pathFunctions,
        primitiveNumericConversionFunctions,
        randomFunctions,
        rangeFunctions,
        regexFunctions,
        resultFunctions,
        runtimeOnlyBridgeFunctions,
        sequenceFunctions,
        serializationFunctions,
        stringBridgeFunctions,
        stringBuilderFunctions,
        stringFunctions,
        systemFunctions,
        testFunctions,
        threadFunctions,
        threadLocalFunctions,
        timeAndPathBridgeFunctions,
        uuidFunctions,
    ] as [[RuntimeABIFunctionSpec]]).flatMap { $0 }

    public static func generateCHeader() -> String {
        var lines: [String] = []
        lines.append("#ifndef KK_RUNTIME_ABI_H")
        lines.append("#define KK_RUNTIME_ABI_H")
        lines.append("")
        lines.append("#include <stdint.h>")
        lines.append("#include <stddef.h>")
        lines.append("")
        lines.append("/* KSwiftK Runtime C ABI \u{2013} spec \(specVersion) */")
        lines.append("/* Auto-generated from RuntimeABISpec. Do NOT edit manually. */")
        lines.append("")
        lines.append("typedef struct KTypeInfo KTypeInfo;")
        lines.append("")

        var currentSection = ""
        for spec in allFunctions {
            if spec.section != currentSection {
                currentSection = spec.section
                lines.append("")
                lines.append("/* --- \(currentSection) --- */")
            }
            lines.append(spec.cDeclaration)
        }

        lines.append("")
        lines.append("#endif /* KK_RUNTIME_ABI_H */")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
