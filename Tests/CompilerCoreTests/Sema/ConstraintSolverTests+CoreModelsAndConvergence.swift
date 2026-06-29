#if canImport(Testing)
@testable import CompilerCore
import Testing

extension ConstraintSolverTests {
    @Test func testSolutionInitStoresAllFields() {
        let sub: [TypeVarID: TypeID] = [TypeVarID(rawValue: 0): TypeID(rawValue: 5)]
        let diag = Diagnostic(
            severity: .error,
            code: "TEST",
            message: "test",
            primaryRange: nil,
            secondaryRanges: []
        )
        let solution = Solution(substitution: sub, isSuccess: false, failure: diag)
        #expect(solution.substitution[TypeVarID(rawValue: 0)] == TypeID(rawValue: 5))
        #expect(!(solution.isSuccess))
        #expect(solution.failure?.code == "TEST")
    }

    @Test func testSolveVarToVarConvergesWithoutChange() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 92)
        let t1 = TypeVarID(rawValue: 93)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t1)),
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        #expect(solution.isSuccess)
        #expect(solution.substitution[t0] == intType)
        #expect(solution.substitution[t1] == intType)
    }

    @Test func testConstraintInitWithBlameRange() {
        let blame = makeRange(start: 10, end: 20)
        let constraint = Constraint(
            kind: .equal,
            left: TypeID(rawValue: 1),
            right: TypeID(rawValue: 2),
            blameRange: blame
        )
        #expect(constraint.kind == .equal)
        #expect(constraint.blameRange == blame)
    }

    @Test func testConstraintInitWithoutBlameRange() {
        let constraint = Constraint(
            kind: .subtype,
            left: TypeID(rawValue: 1),
            right: TypeID(rawValue: 2)
        )
        #expect(constraint.blameRange == nil)
    }

    @Test func testVariableConstraintInitWithBlameRange() {
        let blame = makeRange(start: 0, end: 5)
        let vc = VariableConstraint(
            kind: .supertype,
            left: .variable(TypeVarID(rawValue: 1)),
            right: .type(TypeID(rawValue: 2)),
            blameRange: blame
        )
        #expect(vc.kind == .supertype)
        #expect(vc.blameRange == blame)
    }

    @Test func testVariableConstraintInitWithoutBlameRange() {
        let vc = VariableConstraint(
            kind: .equal,
            left: .type(TypeID(rawValue: 1)),
            right: .variable(TypeVarID(rawValue: 2))
        )
        #expect(vc.blameRange == nil)
    }

    @Test func testSolveBothBoundsUsesLowerCandidate() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 60)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(anyType)),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        #expect(solution.isSuccess)
        #expect(solution.substitution[t0] == intType)
    }

    @Test func testSolveErrorCandidateReportsFailure() throws {
        let (solver, types) = makeDeps()
        let t0 = TypeVarID(rawValue: 70)
        let blame = makeRange(start: 5, end: 8)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(types.errorType), blameRange: blame),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        #expect(!(solution.isSuccess))
        let failure = try #require(solution.failure)
        #expect(failure.message.contains("Failed to infer type variable"))
    }

    @Test func testSolveMultipleVarRelationsConverge() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 80)
        let t1 = TypeVarID(rawValue: 81)
        let t2 = TypeVarID(rawValue: 82)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .variable(t2)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .type(anyType)),
        ]
        let solution = solver.solve(vars: [t0, t1, t2], constraints: constraints, typeSystem: types)

        #expect(solution.isSuccess)
    }

    @Test func testTypeVarIDInvalidAndEquality() {
        #expect(TypeVarID.invalid.rawValue == -1)
        #expect(TypeVarID() == TypeVarID.invalid)
        #expect(TypeVarID(rawValue: 0) != TypeVarID(rawValue: 1))
    }

    @Test func testConstraintOperandEquality() {
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let op1 = ConstraintOperand.type(intType)
        let op2 = ConstraintOperand.type(intType)
        let op3 = ConstraintOperand.variable(TypeVarID(rawValue: 1))
        let op4 = ConstraintOperand.variable(TypeVarID(rawValue: 1))

        #expect(op1 == op2)
        #expect(op3 == op4)
        #expect(op1 != op3)
    }

    @Test func testSolveSupertypeConstraintViolationReportsFailure() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 90)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .type(intType), right: .type(boolType)),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        #expect(!(solution.isSuccess))
    }

    @Test func testFirstRelevantBlameRangeFindsRightSideVariable() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 100)
        let blame = makeRange(start: 20, end: 25)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0), blameRange: blame),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(boolType)),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        #expect(!(solution.isSuccess))
        #expect(solution.failure?.primaryRange == blame)
    }

    @Test func testSolveUnresolvedVariableInConstraintProducesFailure() throws {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 60)
        let tUnknown = TypeVarID(rawValue: 99)
        let blame = makeRange(start: 1, end: 2)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(tUnknown), right: .type(intType), blameRange: blame),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        #expect(!(solution.isSuccess))
        let failure = try #require(solution.failure)
        #expect(failure.message.contains("unresolved variables"))
    }

    @Test func testSolveConflictingBoundsWithMixedTypeTypeConstraints() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 95)
        let blame = makeRange(start: 5, end: 8)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .type(anyType)),
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType), blameRange: blame),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(boolType), blameRange: blame),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        #expect(!(solution.isSuccess))
    }

    @Test func testSolveCandidateErrorTypeFromUpperBoundsOnly() throws {
        let (solver, types) = makeDeps()
        let t0 = TypeVarID(rawValue: 101)
        let blame = makeRange(start: 0, end: 1)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(types.errorType), blameRange: blame),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        #expect(!(solution.isSuccess))
        let failure = try #require(solution.failure)
        #expect(failure.message.contains("Failed to infer"))
    }

    @Test func testTypeVarIDInvalidIsMinusOne() {
        #expect(TypeVarID.invalid.rawValue == -1)
        #expect(TypeVarID().rawValue == -1)
    }

    @Test func testSolveRenderBoundsIncludesEmptyMarker() throws {
        let (solver, types) = makeDeps()
        let t0 = TypeVarID(rawValue: 110)
        let blame = makeRange(start: 60, end: 65)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(types.errorType), blameRange: blame),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)
        #expect(!(solution.isSuccess))
        let failure = try #require(solution.failure)
        #expect(failure.message.contains("lower=[-]"))
    }
}
#endif
