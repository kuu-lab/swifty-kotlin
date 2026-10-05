extension InlineLoweringPass {
    /// Resolve cleanup only after all inline bodies have entered the caller's
    /// lexical scopes. A finally's continuation lies outside its own scope.
    func resolveNonLocalReturnScopes(
        _ body: [KIRInstruction], locations: [SourceRange?],
        arena: KIRArena, unitType: TypeID?, returnType: TypeID? = nil
    ) -> (body: [KIRInstruction], locations: [SourceRange?]) {
        var scopes: [(value: KIRExprID, target: Int32)] = []
        var suspended: [[(value: KIRExprID, target: Int32)]] = []
        var pendingValues: Set<KIRExprID> = []
        for instruction in body {
            switch instruction {
            case let .beginNonLocalReturnScope(value, target):
                scopes.append((value, target))
            case .endNonLocalReturnScope:
                _ = scopes.popLast()
            case let .beginFinallyCleanup(skipping):
                let count = min(skipping, scopes.count)
                suspended.append(Array(scopes.suffix(count)))
                scopes.removeLast(count)
            case .endFinallyCleanup:
                scopes.append(contentsOf: suspended.popLast() ?? [])
            case let .nonLocalReturn(value):
                for scope in scopes {
                    pendingValues.insert(scope.value)
                    if let type = returnType ?? value.flatMap(arena.exprType) ?? unitType {
                        arena.setExprType(type, for: scope.value)
                    }
                }
            default:
                break
            }
        }
        scopes.removeAll()
        suspended.removeAll()
        var output = KIRLoweringEmitContext()
        for (index, instruction) in body.enumerated() {
            output.currentSourceRange = index < locations.count ? locations[index] : nil
            switch instruction {
            case let .beginNonLocalReturnScope(value, target):
                scopes.append((value, target))
            case .endNonLocalReturnScope:
                _ = scopes.popLast()
            case let .beginFinallyCleanup(skipping):
                let count = min(skipping, scopes.count)
                suspended.append(Array(scopes.suffix(count)))
                scopes.removeLast(count)
            case .endFinallyCleanup:
                scopes.append(contentsOf: suspended.popLast() ?? [])
            case .nonLocalReturn, .resumeNonLocalReturn:
                if case let .resumeNonLocalReturn(value) = instruction,
                   !pendingValues.contains(value) {
                    continue
                }
                let value: KIRExprID?
                switch instruction {
                case let .nonLocalReturn(returnValue): value = returnValue
                case let .resumeNonLocalReturn(returnValue): value = returnValue
                default: value = nil
                }
                if let scope = scopes.last {
                    let returned = value ?? arena.appendExpr(.unit, type: unitType)
                    output.append(.copy(from: returned, to: scope.value))
                    output.append(.jump(scope.target))
                } else if let value {
                    output.append(.returnValue(value))
                } else {
                    output.append(.returnUnit)
                }
            default:
                output.append(instruction)
            }
        }
        return (output.instructions, output.instructionLocations)
    }
}
