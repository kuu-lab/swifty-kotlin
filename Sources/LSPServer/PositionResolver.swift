import CompilerCore

/// Maps byte offsets within a file to the AST nodes that enclose them.
/// Used by hover and go-to-definition to find the entity under the cursor.
public struct PositionResolver {
    private let arena: ASTArena
    private let fileID: FileID

    public init(ast: ASTModule, fileID: FileID) {
        arena = ast.arena
        self.fileID = fileID
    }

    /// Returns the narrowest expression whose source range contains `offset`
    /// within this file, or `nil` when no expression matches.
    public func innermostExpr(at offset: Int) -> ExprID? {
        arena.indexedInnermostExpr(at: offset, in: fileID)
    }

}
