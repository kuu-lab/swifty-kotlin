public enum RuntimeABICType: String, CaseIterable, Equatable, Sendable {
    case void
    case uint32 = "uint32_t"
    case uint64 = "uint64_t"
    case int32 = "int32_t"
    case intptr = "intptr_t"
    case opaquePointer = "void *"
    case nullableOpaquePointer = "void * _Nullable"
    case constUInt8Pointer = "const uint8_t *"
    case nullableConstUInt8Pointer = "const uint8_t * _Nullable"
    case nullableUInt8Pointer = "uint8_t * _Nullable"
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
    public let isThrowing: Bool
    public let returnsRawBoolean: Bool

    public init(
        name: String,
        parameters: [RuntimeABIParameter],
        returnType: RuntimeABICType,
        section: String,
        isThrowing: Bool = true,
        returnsRawBoolean: Bool = false
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.section = section
        self.isThrowing = isThrowing
        self.returnsRawBoolean = returnsRawBoolean
    }

    public var cDeclaration: String {
        let params: String = if parameters.isEmpty {
            "void"
        } else {
            parameters.map { "\($0.type.rawValue) \($0.name)" }.joined(separator: ", ")
        }
        return "\(returnType.rawValue) \(name)(\(params));"
    }

    public var parameterTypeStrings: [String] {
        parameters.map(\.type.rawValue)
    }

    public var returnTypeString: String {
        returnType.rawValue
    }
}

public enum RuntimeABISpec {
    public static let specVersion: String = {
        let canonical = allFunctions.map { spec in
            let params = spec.parameters.map { "\($0.name):\($0.type.rawValue)" }.joined(separator: ",")
            return "\(spec.name)|\(spec.returnType.rawValue)|\(params)|\(spec.section)|\(spec.isThrowing)|\(spec.returnsRawBoolean)"
        }.joined(separator: "\n")
        return SHA256.hex(Array(canonical.utf8))
    }()
    public static let allFunctions: [RuntimeABIFunctionSpec] = ([
        abiParityFunctions,
        appleFoundationFunctions,
        arrayFunctions,
        atomicFunctions,
        atomicfuSynchronizationFunctions,
        base64Functions,
        bitwiseFunctions,
        booleanFunctions,
        boxingFunctions,
        callableRefFunctions,
        charFunctions,
        collectionBridgeFunctions,
        collectionFunctions,
        comparatorFunctions,
        consolePrintFunctions,
        coroutineDebugProbesFunctions,
        coroutineFunctions,
        dateFormatFunctions,
        dateTimeFunctions,
        deepRecursiveFunctions,
        delegateFunctions,
        dispatchBridgeFunctions,
        durationFunctions,
        enumFunctions,
        exceptionFunctions,
        fileIOFunctions,
        fileSystemExceptionFunctions,
        gcFunctions,
        ioFileSystemFunctions,
        ioFunctions,
        jdbcFunctions,
        javaNetFunctions,
        kFunctionFunctions,
        kParameterFunctions,
        kPropertyStubFunctions,
        kotlinVersionFunctions,
        localeFunctions,
        mathFunctions,
        memoryFunctions,
        nativeConcurrentFunctions,
        nativeRefFunctions,
        numericRuntimeBridgeFunctions,
        operatorFunctions,
        primitiveNumericConversionFunctions,
        randomFunctions,
        rangeFunctions,
        regexFunctions,
        resultFunctions,
        runtimeOnlyBridgeFunctions,
        securityFunctions,
        sequenceFunctions,
        staticPrimitiveBoxingFunctions,
        stringBuilderFunctions,
        stringFunctions,
        stringParsingFunctions,
        systemFunctions,
        threadLocalFunctions,
        timeAndPathBridgeFunctions,
        uuidFunctions,
    ] as [[RuntimeABIFunctionSpec]]).flatMap { $0 }

    public static let byName: [String: RuntimeABIFunctionSpec] = Dictionary(
        allFunctions.map { ($0.name, $0) },
        uniquingKeysWith: { first, _ in first }
    )
}
