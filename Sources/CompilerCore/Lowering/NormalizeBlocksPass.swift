
final class NormalizeBlocksPass: LoweringPass, ParallelLoweringPass {
    static let name = "NormalizeBlocks"

    func shouldRun(module: KIRModule, ctx _: KIRContext) -> Bool {
        module.ensureFeaturesScanned()
        return !module.features.isDisjoint(with: [.hasBeginEndBlock, .hasNonTerminatedFunction])
    }

    func run(module: KIRModule, ctx _: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            updated.replaceBody(function.body.filter { instruction in
                switch instruction {
                case .beginBlock, .endBlock:
                    false
                default:
                    true
                }
            })
            if let last = updated.body.last {
                switch last {
                case .returnUnit, .returnValue:
                    break
                default:
                    var normalizedBody = updated.body
                    normalizedBody.append(.returnUnit)
                    updated.replaceBody(normalizedBody)
                }
            } else {
                updated.replaceBody([.returnUnit])
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}
