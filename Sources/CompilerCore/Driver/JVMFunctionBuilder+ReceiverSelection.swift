extension JVMFunctionBuilder {
    func implicitExtensionReceiver(_ id: ExprID) -> JVMValue? {
        let bindings = program.sema.bindings
        let memberExtension = bindings.callBinding(for: id).flatMap { program.sema.symbols.memberExtensionOwnerSymbol(for: $0.chosenCallee) } != nil
        return bindings.implicitExtensionReceiver(for: id).flatMap { contextualReceivers[$0] }
            ?? (memberExtension ? nil : bindings.implicitReceiverOuterReceiver(for: id).flatMap { contextualReceivers[$0] })
            ?? extensionValue ?? thisValue
    }
}
