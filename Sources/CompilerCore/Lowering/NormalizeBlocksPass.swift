
final class NormalizeBlocksPass: LoweringPass, ParallelLoweringPass {
    static let name = "NormalizeBlocks"

    func shouldRun(module: KIRModule, ctx _: KIRContext) -> Bool {
        module.ensureFeaturesScanned()
        return !module.features.isDisjoint(with: [.hasBeginEndBlock, .hasNonTerminatedFunction])
    }

    func run(module: KIRModule, ctx _: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            var keptBody: [KIRInstruction] = []
            var keptLocations: [SourceRange?] = []
            for (index, instruction) in function.body.enumerated() {
                switch instruction {
                case .beginBlock, .endBlock:
                    continue
                default:
                    keptBody.append(instruction)
                    keptLocations.append(
                        index < function.instructionLocations.count
                            ? function.instructionLocations[index]
                            : nil
                    )
                }
            }
            updated.replaceBody(keptBody, locations: keptLocations)
            if let last = updated.body.last {
                switch last {
                case .returnUnit, .returnValue:
                    break
                default:
                    var normalizedBody = updated.body
                    var normalizedLocations = updated.instructionLocations
                    normalizedBody.append(.returnUnit)
                    normalizedLocations.append(nil)
                    updated.replaceBody(normalizedBody, locations: normalizedLocations)
                }
            } else {
                updated.replaceBody([.returnUnit], locations: [nil])
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}
