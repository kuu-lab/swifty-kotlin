public extension RuntimeABISpec {
    static let kotlinVersionFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_kotlin_version_current",
            parameters: [],
            returnType: .intptr,
            section: "KotlinVersion",
            isThrowing: false
        ),
    ]
}
