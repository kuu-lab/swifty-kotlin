
/// Dispatch hub for KIR lowering. Replaces the monolithic extension-based splitting
/// of `BuildKIRPhase` with independent delegate classes.
///
/// Each delegate holds an `unowned` back-reference to this driver so that mutually
/// recursive calls (e.g. `lowerExpr` → `lowerCallExpr` → `lowerExpr`) can be
/// dispatched through the driver rather than sharing a single fat class instance.
final class KIRLoweringDriver {
    let ctx: KIRLoweringContext

    // Lazy to break initialization ordering.
    private(set) lazy var exprLowerer = ExprLowerer(driver: self)
    private(set) lazy var callLowerer = CallLowerer(driver: self)
    private(set) lazy var controlFlowLowerer = ControlFlowLowerer(driver: self)
    private(set) lazy var memberLowerer = MemberLowerer(driver: self)
    private(set) lazy var lambdaLowerer = LambdaLowerer(driver: self)
    private(set) lazy var objectLiteralLowerer = ObjectLiteralLowerer(driver: self)
    private(set) lazy var callSupportLowerer = CallSupportLowerer(driver: self)

    /// Stateless utilities (no back-reference needed). Lowering only folds
    /// non-`const` expressions here (`const val` values come pre-evaluated
    /// from Sema), so floating-point comparisons follow IEEE 754.
    let constantCollector = ConstantCollector(floatingPointComparisonSemantics: .ieee754)

    init(ctx: KIRLoweringContext) {
        self.ctx = ctx
    }

    func lowerExpr(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        exprLowerer.lowerExpr(
            exprID,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
    }

    func lowerExpr(
        _ exprID: ExprID,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        exprLowerer.lowerExpr(
            exprID,
            shared: shared,
            emit: &instructions
        )
    }
}
