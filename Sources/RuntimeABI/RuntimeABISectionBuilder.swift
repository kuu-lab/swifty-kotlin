/// Compact constructor for `RuntimeABIFunctionSpec` tables that share one C-header `section`.
///
/// One call replaces the ~10-line `RuntimeABIFunctionSpec(name:parameters:returnType:section:isThrowing:)`
/// literal. The spec name stays a plain string literal on the call line, so `grep '"kk_foo"'` still
/// finds exactly one definition line.
///
///     private let abi = RuntimeABISectionBuilder("Bitwise")
///     abi.nt("kk_bitwise_and", "a b")                      // non-throwing, (a, b: intptr) -> intptr
///     abi.th("kk_op_div", "lhs rhs outThrown")             // throwing, trailing outThrown out-parameter
///     abi.nt("kk_foo_log", "msg:constUInt8Pointer", ret: .void)
///     abi.nt("kk_foo_isEmpty", "receiver", raw: true)      // returns a raw 0/1 Boolean
///
/// Parameter string: whitespace-separated tokens, each `name` (type `.intptr`) or `name:type`, where
/// `type` is a `RuntimeABICType` case name. The bare name `outThrown` is shorthand for
/// `outThrown:nullableIntptrPointer`.
///
/// `th` / `nt` choose `RuntimeABIFunctionSpec.isThrowing` only; neither adds nor removes an `outThrown`
/// parameter. The two are independent fields in the existing spec data, so list `outThrown` explicitly.
struct RuntimeABISectionBuilder: Sendable {
    let section: String

    init(_ section: String) {
        self.section = section
    }

    /// A callee that may throw (`isThrowing: true`, the `RuntimeABIFunctionSpec` default).
    func th(
        _ name: String,
        _ parameters: String = "",
        ret: RuntimeABICType = .intptr,
        raw: Bool = false
    ) -> RuntimeABIFunctionSpec {
        make(name, parameters, ret: ret, raw: raw, isThrowing: true)
    }

    /// A callee that never throws (`isThrowing: false`).
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

    /// Keyed by case name (`String(describing:)`), so a new `RuntimeABICType` case is spellable
    /// in the DSL without touching a second table.
    private static let typeByToken: [String: RuntimeABICType] = Dictionary(
        uniqueKeysWithValues: RuntimeABICType.allCases.map { (String(describing: $0), $0) }
    )

    /// A malformed table entry traps at first access of `RuntimeABISpec`, which every ABI test hits.
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
