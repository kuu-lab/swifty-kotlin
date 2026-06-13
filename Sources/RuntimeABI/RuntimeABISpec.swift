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

    public init(
        name: String,
        parameters: [RuntimeABIParameter],
        returnType: RuntimeABICType,
        section: String
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.section = section
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


public enum RuntimeABISpec {
    public static let specVersion = "J33"

    public static let allFunctions: [RuntimeABIFunctionSpec] = ([
        abiParityFunctions,
        arrayFunctions,
        atomicFunctions,
        base64Functions,
        bigIntegerFunctions,
        bitwiseFunctions,
        booleanFunctions,
        boxingFunctions,
        broadcastChannelFunctions,
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
