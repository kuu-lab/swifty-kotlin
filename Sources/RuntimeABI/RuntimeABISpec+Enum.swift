public extension RuntimeABISpec {
    static let enumFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_enum_hash_code",
            parameters: [
                RuntimeABIParameter(name: "ordinal", type: .intptr),
                RuntimeABIParameter(name: "classID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Enum",
            isThrowing: false
        ),
    ]
}
