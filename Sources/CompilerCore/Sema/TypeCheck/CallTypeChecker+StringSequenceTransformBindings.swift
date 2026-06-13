/// Binding for `String.chunkedSequence(transform:)` and
/// `String.windowedSequence(transform:)` overloads (STDLIB-CHUNKED / WINDOWED).
///
/// Split out from `CallTypeChecker+MemberCallInference.swift`.
extension CallTypeChecker {
    func tryBindStringChunkedSequenceTransform(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        // chunked_sequence_transform synthetic stub removed - now implemented in Kotlin stdlib source
        return nil
    }

    func tryBindStringWindowedSequenceTransform(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        // windowedSequence_transform synthetic stub removed - now implemented in Kotlin stdlib source
        return nil
    }
}
