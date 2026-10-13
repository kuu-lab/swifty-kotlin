import CompilerCore

public func makeBackendPhases() -> [CompilerPhase] {
    let session = LLVMBackendSession()
    return [CodegenPhase(session: session), LinkPhase(session: session)]
}
