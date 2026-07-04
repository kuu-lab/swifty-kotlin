public extension RuntimeABISpec {
    static let hexFormatFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_hexformat_default",
            parameters: [],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_hexformat_create",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_hexformat_upperCase",
            parameters: [
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_hexformat_bytes",
            parameters: [
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_toHexString",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_toHexString",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_bytearray_toHexString",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToInt_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToShort_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToUByte_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToUShort_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToUInt_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToULong_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToLong_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToByteArray_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_hexToUByteArray_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "HexFormat"
        ),
    ]
}
