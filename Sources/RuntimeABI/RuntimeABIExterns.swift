/// `RuntimeABISpec` is the single source of truth. This type keeps the
/// compiler/test-facing extern view stable without duplicating hundreds of
/// handwritten declarations.
public enum RuntimeABIExterns {
    public struct ExternDecl: Equatable, Sendable {
        public let name: String
        public let parameterTypes: [String]
        public let returnType: String

        public init(name: String, parameterTypes: [String], returnType: String) {
            self.name = name
            self.parameterTypes = parameterTypes
            self.returnType = returnType
        }

        public init(spec: RuntimeABIFunctionSpec) {
            self.init(
                name: spec.name,
                parameterTypes: spec.parameterTypeStrings,
                returnType: spec.returnTypeString
            )
        }
    }

    public static let allExterns = RuntimeABISpec.allFunctions.map(ExternDecl.init(spec:))

    private static let externsByName: [String: ExternDecl] = Dictionary(
        uniqueKeysWithValues: allExterns.map { ($0.name, $0) }
    )

    public static func externDecl(named name: String) -> ExternDecl? {
        externsByName[name]
    }
}
