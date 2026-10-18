import CompilerCore

public struct PositionResolver {
    private let arena: ASTArena
    private let fileID: FileID

    public init(ast: ASTModule, fileID: FileID) {
        arena = ast.arena
        self.fileID = fileID
    }

    public func innermostExpr(at offset: Int) -> ExprID? {
        arena.indexedInnermostExpr(at: offset, in: fileID)
    }

}
