struct RuntimeABISectionBuilder: Sendable {
    let section: String

    init(_ section: String) {
        self.section = section
    }

    func th(
        _ name: String,
        _ parameters: String = "",
        ret: RuntimeABICType = .intptr,
        raw: Bool = false
    ) -> RuntimeABIFunctionSpec {
        make(name, parameters, ret: ret, raw: raw, isThrowing: true)
    }

    func nt(
        _ name: String,
        _ parameters: String = "",
        ret: RuntimeABICType = .intptr,
        raw: Bool = false
    ) -> RuntimeABIFunctionSpec {
        make(name, parameters, ret: ret, raw: raw, isThrowing: false)
    }

    private func make(
        _ name: String,
        _ parameters: String,
        ret: RuntimeABICType,
        raw: Bool,
        isThrowing: Bool
    ) -> RuntimeABIFunctionSpec {
        RuntimeABIFunctionSpec(
            name: name,
            parameters: Self.parse(parameters, specName: name),
            returnType: ret,
            section: section,
            isThrowing: isThrowing,
            returnsRawBoolean: raw
        )
    }

    private static let typeByToken: [String: RuntimeABICType] = Dictionary(
        uniqueKeysWithValues: RuntimeABICType.allCases.map { (String(describing: $0), $0) }
    )

    static func parse(_ text: String, specName: String) -> [RuntimeABIParameter] {
        text.split(separator: " ").map { token in
            let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts[0])
            guard !name.isEmpty else {
                preconditionFailure("RuntimeABISectionBuilder: empty parameter name in \(specName): '\(text)'")
            }
            guard parts.count == 2 else {
                return RuntimeABIParameter(name: name, type: name == "outThrown" ? .nullableIntptrPointer : .intptr)
            }
            guard let type = typeByToken[String(parts[1])] else {
                preconditionFailure("RuntimeABISectionBuilder: unknown type '\(parts[1])' in \(specName): '\(text)'")
            }
            return RuntimeABIParameter(name: name, type: type)
        }
    }
}
