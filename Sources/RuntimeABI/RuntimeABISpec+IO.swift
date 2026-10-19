// swiftlint:disable file_length

public extension RuntimeABISpec {
    static let ioFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_readline_raw",
            parameters: [],
            returnType: .intptr,
            section: "IO",
            isThrowing: false,
        ),
    ]
}
