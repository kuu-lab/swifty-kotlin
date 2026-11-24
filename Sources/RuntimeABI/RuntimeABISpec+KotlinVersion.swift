private let abi = RuntimeABISectionBuilder("KotlinVersion")

public extension RuntimeABISpec {
    static let kotlinVersionFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_kotlin_version_current"),
    ]
}
