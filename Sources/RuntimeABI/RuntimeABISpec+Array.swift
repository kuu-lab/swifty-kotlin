
/// `RuntimeABISpec.arrayFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {

    static let arrayFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_array_new",
            parameters: [
                RuntimeABIParameter(name: "length", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_of_nulls",
            parameters: [
                RuntimeABIParameter(name: "length", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_new",
            parameters: [
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "classId", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_type_id",
            parameters: [
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array"
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
            section: "Array"
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
            section: "Array"
        ),
    ]
}
