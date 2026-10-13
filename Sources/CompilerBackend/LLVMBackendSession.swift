/// Retains the verified LLVM library for one Codegen/Link pipeline only.
/// Contexts, modules, and target machines remain owned by each emitter.
final class LLVMBackendSession {
    private var bindings: LLVMCAPIBindings?

    func loadBindings() -> LLVMCAPIBindings? {
        if let bindings { return bindings }
        // Cache successful loads only; preserve trust checks and the context
        // lifecycle smoke test on the first load of each compilation.
        let loaded = LLVMCAPIBindings.loadUsable()
        bindings = loaded
        return loaded
    }
}
