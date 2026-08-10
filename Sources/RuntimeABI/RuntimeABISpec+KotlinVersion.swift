public extension RuntimeABISpec {
    // KSP-610: the KotlinVersion class is bundled Kotlin source; only the
    // build-time version constant remains as a native bridge.
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
