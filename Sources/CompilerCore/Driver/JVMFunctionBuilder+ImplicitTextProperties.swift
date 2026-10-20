extension JVMFunctionBuilder {
    func implicitTextProperty(_ id: ExprID, name: InternedString) throws -> JVMValue? {
        let bindings = program.sema.bindings
        guard !scopes.contains(where: { $0[name] != nil }), context.interner.resolve(name) == "length",
              bindings.implicitReceiverMemberNames[id] == name else { return nil }
        // A builtin property has no source JVMProperty/getter plan. Its bound
        // receiver still follows the same lexical tower as explicit access.
        let selected = bindings.implicitReceiverOuterReceiver(for: id)
        guard let receiver = selected.flatMap({ contextualReceivers[$0] }) ?? extensionValue ?? thisValue else {
            throw fail("Missing implicit JVM text property receiver.", id)
        }
        guard receiver.type.isText else { return nil }
        return try textLength(receiver)
    }
}
