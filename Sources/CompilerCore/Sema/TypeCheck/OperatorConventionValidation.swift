extension TypeCheckSemaPhase {
    /// KUU-3149: an `operator` function must satisfy the arity of its
    /// convention name — kotlinc rejects a two-parameter `plus` or a
    /// parameterized `unaryPlus`/`componentN` at the declaration site.
    /// Unrecognized names are left alone: the separate "operator modifier
    /// is inapplicable" name check is intentionally out of scope.
    func validateOperatorConventions(
        ast: ASTModule,
        interner: StringInterner,
        diagnostics: DiagnosticEngine
    ) {
        for decl in ast.arena.decls {
            guard case let .funDecl(function) = decl,
                  function.modifiers.contains(.operator)
            else { continue }
            checkOperatorArity(
                name: interner.resolve(function.name),
                parameterCount: function.valueParams.count,
                range: function.range,
                diagnostics: diagnostics
            )
        }
        for (index, expression) in ast.arena.exprs.enumerated() {
            guard case let .localFunDecl(name, _, valueParams, _, _, _, range, _, _) = expression,
                  ast.arena.isOperatorFunction(ExprID(rawValue: Int32(index)))
            else { continue }
            checkOperatorArity(
                name: interner.resolve(name),
                parameterCount: valueParams.count,
                range: range,
                diagnostics: diagnostics
            )
        }
    }

    private func checkOperatorArity(
        name: String,
        parameterCount: Int,
        range: SourceRange,
        diagnostics: DiagnosticEngine
    ) {
        if Self.zeroParameterOperators.contains(name) || isComponentNName(name) {
            if parameterCount != 0 {
                diagnostics.error(
                    "KSWIFTK-SEMA-0436",
                    "'\(name)' must have no value parameters.",
                    range: range
                )
            }
            return
        }
        if Self.singleParameterOperators.contains(name) {
            if parameterCount != 1 {
                diagnostics.error(
                    "KSWIFTK-SEMA-0436",
                    "'\(name)' must have a single value parameter.",
                    range: range
                )
            }
            return
        }
        if let fixed = Self.fixedParameterCounts[name], parameterCount != fixed {
            diagnostics.error(
                "KSWIFTK-SEMA-0436",
                "'\(name)' must have exactly \(fixed) value parameters.",
                range: range
            )
            return
        }
        if let minimum = Self.minimumParameterCounts[name], parameterCount < minimum {
            diagnostics.error(
                "KSWIFTK-SEMA-0436",
                "'\(name)' must have at least \(minimum) value parameter\(minimum == 1 ? "" : "s").",
                range: range
            )
        }
    }

    private static let zeroParameterOperators: Set<String> = [
        "inc", "dec", "unaryPlus", "unaryMinus", "not",
        "iterator", "next", "hasNext",
    ]

    private static let singleParameterOperators: Set<String> = [
        "plus", "minus", "times", "div", "rem", "mod",
        "rangeTo", "rangeUntil", "contains", "compareTo", "equals",
        "plusAssign", "minusAssign", "timesAssign", "divAssign",
        "remAssign", "modAssign",
    ]

    private static let fixedParameterCounts: [String: Int] = [
        "provideDelegate": 2, "getValue": 2, "setValue": 3,
    ]

    private static let minimumParameterCounts: [String: Int] = [
        "get": 1, "set": 2,
    ]

    private func isComponentNName(_ name: String) -> Bool {
        let prefix = "component"
        guard name.hasPrefix(prefix) else { return false }
        let suffix = name.dropFirst(prefix.count)
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber) && Int(suffix).map { $0 >= 1 } == true
    }
}
