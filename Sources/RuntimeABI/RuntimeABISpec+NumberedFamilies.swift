func numberedUnaryRuntimeABIFunctionSpecs(
    prefix: String,
    range: ClosedRange<Int>,
    parameterName: String,
    parameterType: RuntimeABICType = .intptr,
    returnType: RuntimeABICType = .intptr,
    section: String,
    isThrowing: Bool = true
) -> [RuntimeABIFunctionSpec] {
    range.map { index in
        RuntimeABIFunctionSpec(
            name: "\(prefix)\(index)",
            parameters: [RuntimeABIParameter(name: parameterName, type: parameterType)],
            returnType: returnType,
            section: section,
            isThrowing: isThrowing
        )
    }
}
