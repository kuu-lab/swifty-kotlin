/// Per-caller resource limits shared by rescans and nested lambda splices.
final class InlineExpansionBudget {
    struct Limits {
        var work = 1_000_000
        var instructions = 100_000
        var expressions = 200_000
        var nesting = 128
    }

    let limits: Limits
    private let initialExpressionCount: Int
    private(set) var work = 0
    private var nesting = 0
    var ancestry: [SymbolID] = []

    init(arena: KIRArena, limits: Limits = Limits()) {
        self.limits = limits
        initialExpressionCount = arena.expressions.count
    }

    func consumeWork(_ count: Int, arena: KIRArena) -> Bool {
        guard count <= limits.work - work,
              arena.expressions.count - initialExpressionCount <= limits.expressions
        else { return false }
        work += count
        return true
    }

    func enter(_ function: KIRFunction, arena: KIRArena) -> Bool {
        guard consumeWork(ancestry.count, arena: arena),
              !ancestry.contains(function.symbol), nesting < limits.nesting,
              function.body.count <= limits.instructions,
              consumeWork(max(1, function.body.count), arena: arena)
        else { return false }
        ancestry.append(function.symbol)
        nesting += 1
        return true
    }

    func leave() {
        ancestry.removeLast()
        nesting -= 1
    }

    func permitsOutput(_ count: Int, arena: KIRArena) -> Bool {
        count <= limits.instructions
            && arena.expressions.count - initialExpressionCount <= limits.expressions
    }

    func permitsAdditional(_ count: Int, outputCount: Int, arena: KIRArena) -> Bool {
        count <= limits.instructions - outputCount
            && count <= limits.expressions - (arena.expressions.count - initialExpressionCount)
    }
}
