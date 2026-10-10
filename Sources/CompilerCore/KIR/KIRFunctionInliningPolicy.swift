// Keep callable-reference thunks consistent with declaration auto-inlining.
func shouldAutoInlineFunction(
    _ function: FunDecl,
    parameterTypes: [TypeID],
    types: TypeSystem
) -> Bool {
    let hasLambdaParam = parameterTypes.contains { type in
        if case .functionType = types.kind(of: type) { return true }
        return false
    }
    let hasNoInlineAnnotation = function.annotations.contains { annotation in
        annotation.name == "NoInline" || annotation.name == "kotlin.native.NoInline"
            || annotation.name == "KsNoInline" || annotation.name == "kotlin.internal.KsNoInline"
    }
    return hasLambdaParam && !function.isSuspend && !hasNoInlineAnnotation
}
