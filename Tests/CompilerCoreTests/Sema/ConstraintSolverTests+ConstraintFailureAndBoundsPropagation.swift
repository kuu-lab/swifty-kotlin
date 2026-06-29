#if canImport(Testing)
@testable import CompilerCore
import Testing

extension ConstraintSolverTests {
    @Test func testSolveHandlesUnregisteredVariablesInConstraints() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 0)
        let t1 = TypeVarID(rawValue: 1) // not in vars
        let t2 = TypeVarID(rawValue: 2) // not in vars
        let t3 = TypeVarID(rawValue: 3) // not in vars

        // Only t0 is in vars; t1, t2, t3 are unregistered.
        // This exercises dictionary default-value closures in the solver:
        //   - lowerBounds default for t1 (type-to-variable constraint)
        //   - upperBounds default for t1 (var-to-var propagation read)
        //   - upperBounds default for t1 (var-to-var propagation write from t2)
        //   - lowerBounds default for t2 (var-to-var propagation write from t1)
        //   - lowerBounds default for t3 (var-to-var propagation read)
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .variable(t2)),
            VariableConstraint(kind: .subtype, left: .variable(t3), right: .variable(t0)),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)
        // t1 is not in vars so resolve returns nil → failure
        #expect(!(solution.isSuccess))
        #expect(solution.failure != nil)
    }

    @Test func testSolvePostSubstitutionEqualConstraintViolationMessage() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 120)
        let blame = makeRange(start: 70, end: 75)

        // t0 gets bound to intType via lower bound, then equal constraint
        // forces post-substitution check: intType == boolType fails
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(boolType), blameRange: blame),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)
        #expect(!(solution.isSuccess))
        #expect(solution.failure != nil)
    }

    // MARK: - Empty constraints with multiple variables

    @Test func testSolveEmptyConstraintsWithManyVariablesAllGetErrorType() {
        let (solver, types) = makeDeps()
        let vars = (0 ..< 5).map { TypeVarID(rawValue: Int32(200 + $0)) }

        let solution = solver.solve(
            vars: vars,
            constraints: [] as [VariableConstraint],
            typeSystem: types
        )

        #expect(solution.isSuccess)
        #expect(solution.failure == nil)
        for v in vars {
            #expect(solution.substitution[v] == types.errorType)
        }
    }

    @Test func testSolveEmptyConstraintsWithSingleVariableGetsErrorType() {
        let (solver, types) = makeDeps()
        let t0 = TypeVarID(rawValue: 210)

        let solution = solver.solve(
            vars: [t0],
            constraints: [] as [VariableConstraint],
            typeSystem: types
        )

        #expect(solution.isSuccess)
        #expect(solution.substitution[t0] == types.errorType)
    }

    @Test func testSolveEmptyConstraintsEmptyVarsSucceeds() {
        let (solver, types) = makeDeps()

        let solution = solver.solve(
            vars: [],
            constraints: [] as [VariableConstraint],
            typeSystem: types
        )

        #expect(solution.isSuccess)
        #expect(solution.substitution.isEmpty)
    }

    // MARK: - Circular variable constraints

    @Test func testSolveCircularTwoVariablesWithSharedBound() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 220)
        let t1 = TypeVarID(rawValue: 221)

        // t0 <: t1, t1 <: t0 forms a cycle; both get intType from lower bound
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .variable(t0)),
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        #expect(solution.isSuccess)
        #expect(solution.substitution[t0] == intType)
        #expect(solution.substitution[t1] == intType)
    }

    @Test func testSolveCircularThreeVariablesWithSharedBound() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 230)
        let t1 = TypeVarID(rawValue: 231)
        let t2 = TypeVarID(rawValue: 232)

        // circular: t0 <: t1 <: t2 <: t0, with intType lower on t0 and anyType upper on t2
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .variable(t2)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .type(anyType)),
        ]
        let solution = solver.solve(vars: [t0, t1, t2], constraints: constraints, typeSystem: types)

        #expect(solution.isSuccess)
        #expect(solution.substitution[t0] == intType)
        #expect(solution.substitution[t1] == intType)
        #expect(solution.substitution[t2] == intType)
    }

    @Test func testSolveCircularVariablesNoBoundsAllGetErrorType() {
        let (solver, types) = makeDeps()
        let t0 = TypeVarID(rawValue: 240)
        let t1 = TypeVarID(rawValue: 241)

        // circular with no concrete bounds → both remain empty → errorType
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .variable(t0)),
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        #expect(solution.isSuccess)
        #expect(solution.substitution[t0] == types.errorType)
        #expect(solution.substitution[t1] == types.errorType)
    }

    // MARK: - Mixed constraint types (subtype, equal, supertype)

    @Test func testSolveMixedConstraintKindsOnSingleVariable() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 250)

        // equal binds both lower and upper to intType,
        // subtype adds upper bound anyType,
        // supertype adds lower bound intType
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(anyType)),
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType)),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        #expect(solution.isSuccess)
        #expect(solution.substitution[t0] == intType)
    }

    @Test func testSolveMixedConstraintKindsAcrossMultipleVariables() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.stringType
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 260)
        let t1 = TypeVarID(rawValue: 261)
        let t2 = TypeVarID(rawValue: 262)

        let constraints: [VariableConstraint] = [
            // t0 == intType
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            // t1 :> stringType (lower bound = stringType)
            VariableConstraint(kind: .supertype, left: .variable(t1), right: .type(stringType)),
            // t1 <: anyType (upper bound = anyType)
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .type(anyType)),
            // t2 <: t1 (variable-to-variable subtype)
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .variable(t1)),
            // t2 :> stringType (lower bound on t2)
            VariableConstraint(kind: .supertype, left: .variable(t2), right: .type(stringType)),
        ]
        let solution = solver.solve(vars: [t0, t1, t2], constraints: constraints, typeSystem: types)

        #expect(solution.isSuccess)
        #expect(solution.substitution[t0] == intType)
        #expect(solution.substitution[t1] == stringType)
        #expect(solution.substitution[t2] == stringType)
    }

    @Test func testSolveMixedConstraintKindsWithTypeTypeConflictFails() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 270)

        // type-type equal constraint fails: Int == Bool
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .type(intType), right: .type(boolType)),
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType)),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        #expect(!(solution.isSuccess))
        #expect(solution.substitution[t0] == types.errorType)
    }

    @Test func testSolveSupertypeTypeTypeConstraintSatisfied() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 275)

        // supertype type-type: Any :> Int → normalized to Int <: Any (true)
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .type(anyType), right: .type(intType)),
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        #expect(solution.isSuccess)
        #expect(solution.substitution[t0] == intType)
    }

    // MARK: - Multiple failure scenario combinations

    @Test func testSolveMultipleConflictingBoundsReportsFirstFailure() throws {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let stringType = types.stringType
        let t0 = TypeVarID(rawValue: 280)
        let t1 = TypeVarID(rawValue: 281)
        let blame0 = makeRange(start: 100, end: 105)
        let blame1 = makeRange(start: 110, end: 115)

        // t0 has conflicting bounds: lower=Int, upper=Bool
        // t1 has conflicting bounds: lower=String, upper=Int
        // Solver should fail on first variable it encounters
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType), blameRange: blame0),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(boolType), blameRange: blame0),
            VariableConstraint(kind: .supertype, left: .variable(t1), right: .type(stringType), blameRange: blame1),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .type(intType), blameRange: blame1),
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        #expect(!(solution.isSuccess))
        let failure = try #require(solution.failure)
        #expect(failure.code == "KSWIFTK-TYPE-0001")
        #expect(failure.message.contains("Conflicting bounds"))
        #expect(failure.primaryRange == blame0)
    }
}
#endif
