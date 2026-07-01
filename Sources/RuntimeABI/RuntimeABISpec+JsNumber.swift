public extension RuntimeABISpec {
    static let jsNumberFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_js_number_toDouble",
            parameters: [
                RuntimeABIParameter(name: "thisRaw", type: .intptr),
            ],
            returnType: .double,
            section: "JsNumber",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_js_number_toInt",
            parameters: [
                RuntimeABIParameter(name: "thisRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "JsNumber",
            isThrowing: false
        ),
    ]
}
