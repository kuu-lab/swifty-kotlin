public extension RuntimeABISpec {
    static let dateFormatFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_simple_date_format_parse",
            parameters: [
                RuntimeABIParameter(name: "patternRaw", type: .intptr),
                RuntimeABIParameter(name: "sourceRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "DateFormat",
            isThrowing: false
        ),
    ]
}
