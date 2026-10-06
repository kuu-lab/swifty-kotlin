extension InlineLoweringPass {
    private struct ReturnScope {
        let value: KIRExprID
        let target: Int32
        let function: KIRReturnTarget?
    }

    private struct ReturnRoute {
        let destination: KIRExprID?
        let value: KIRExprID
    }

    /// Resolve cleanup after expansion, without crossing the named return target.
    func resolveNonLocalReturnScopes(
        _ body: [KIRInstruction], locations: [SourceRange?],
        arena: KIRArena, unitType: TypeID?, returnType: TypeID? = nil
    ) -> (body: [KIRInstruction], locations: [SourceRange?]) {
        var scopes: [ReturnScope] = []
        var suspended: [[(Int, ReturnScope)]] = []
        var routes: [KIRExprID: [ReturnRoute]] = [:]
        var discriminators: [KIRExprID: KIRExprID] = [:]
        var labels = InlineLabelAllocator(callerBody: body)

        func updateScopes(_ instruction: KIRInstruction) {
            switch instruction {
            case let .beginNonLocalReturnScope(value, target, function):
                scopes.append(ReturnScope(value: value, target: target, function: function))
            case .endNonLocalReturnScope:
                _ = scopes.popLast()
            case let .beginFinallyCleanup(skipping):
                let indices = scopes.indices.filter { scopes[$0].function == nil }.suffix(skipping)
                suspended.append(indices.map { ($0, scopes[$0]) })
                for index in indices.reversed() { scopes.remove(at: index) }
            case .endFinallyCleanup:
                for (index, scope) in suspended.popLast() ?? [] { scopes.insert(scope, at: index) }
            default:
                break
            }
        }

        func destination(for target: KIRReturnTarget?) -> KIRExprID? {
            guard let target else { return nil }
            return scopes.last { $0.function == target }?.value
        }

        func cleanupScopes(to destination: KIRExprID?) -> [ReturnScope] {
            let start = destination.flatMap { dest in scopes.lastIndex { $0.value == dest } }.map { $0 + 1 } ?? 0
            return scopes.dropFirst(start).filter { $0.function == nil }
        }

        for instruction in body {
            updateScopes(instruction)
            guard case let .nonLocalReturn(value, target) = instruction else { continue }
            let dest = destination(for: target)
            let type = dest == nil
                ? returnType ?? value.flatMap(arena.exprType) ?? unitType
                : dest.flatMap(arena.exprType) ?? value.flatMap(arena.exprType)
            for scope in cleanupScopes(to: dest) {
                guard !(routes[scope.value] ?? []).contains(where: { $0.destination == dest }) else { continue }
                let slot = routes[scope.value] == nil ? scope.value : arena.appendTemporary(type: type)
                if let type { arena.setExprType(type, for: slot) }
                routes[scope.value, default: []].append(ReturnRoute(destination: dest, value: slot))
            }
        }
        for (slot, choices) in routes where choices.count > 1 {
            discriminators[slot] = arena.appendTemporary(type: nil)
        }
        scopes.removeAll()
        suspended.removeAll()
        var output = KIRLoweringEmitContext()

        func emitReturn(_ value: KIRExprID?, to destination: KIRExprID?) {
            if let cleanup = cleanupScopes(to: destination).last,
               let index = routes[cleanup.value]?.firstIndex(where: { $0.destination == destination }),
               let route = routes[cleanup.value]?[index] {
                let returned = value ?? arena.appendExpr(.unit, type: unitType)
                output.append(.copy(from: returned, to: route.value))
                if let discriminator = discriminators[cleanup.value] {
                    output.append(.constValue(result: discriminator, value: .intLiteral(Int64(index))))
                }
                output.append(.jump(cleanup.target))
            } else if let destination, let scope = scopes.last(where: { $0.value == destination }) {
                let returned = value ?? arena.appendExpr(.unit, type: unitType)
                output.append(.copy(from: returned, to: scope.value))
                output.append(.jump(scope.target))
            } else if let value {
                output.append(.returnValue(value))
            } else {
                output.append(.returnUnit)
            }
        }

        for (index, instruction) in body.enumerated() {
            output.currentSourceRange = index < locations.count ? locations[index] : nil
            updateScopes(instruction)
            switch instruction {
            case .beginNonLocalReturnScope, .endNonLocalReturnScope, .beginFinallyCleanup, .endFinallyCleanup:
                break
            case let .nonLocalReturn(value, target):
                emitReturn(value, to: destination(for: target))
            case let .resumeNonLocalReturn(slot):
                guard let choices = routes[slot], let first = choices.first else { continue }
                if let discriminator = discriminators[slot] {
                    let branchLabels = choices.map { _ in labels.allocateCallerLabel() }
                    for choiceIndex in choices.indices.dropLast() {
                        let tag = arena.appendTemporary(type: nil)
                        output.append(.constValue(result: tag, value: .intLiteral(Int64(choiceIndex))))
                        output.append(.jumpIfEqual(lhs: discriminator, rhs: tag, target: branchLabels[choiceIndex]))
                    }
                    output.append(.jump(branchLabels[choices.count - 1]))
                    for (choice, label) in zip(choices, branchLabels) {
                        output.append(.label(label))
                        emitReturn(choice.value, to: choice.destination)
                    }
                } else {
                    emitReturn(first.value, to: first.destination)
                }
            default:
                output.append(instruction)
            }
        }
        return (output.instructions, output.instructionLocations)
    }
}
