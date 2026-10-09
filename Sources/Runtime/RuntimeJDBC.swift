import CSQLite
import Foundation

private final class RuntimeJDBCConnectionBox {
    var database: OpaquePointer?
    var isClosed = false
    var statements: [RuntimeJDBCStatementBox] = []

    init(database: OpaquePointer) {
        self.database = database
    }
}

private final class RuntimeJDBCStatementBox {
    weak var connection: RuntimeJDBCConnectionBox?
    let isPrepared: Bool
    var sqliteStatement: OpaquePointer?
    var isClosed = false
    weak var resultSet: RuntimeJDBCResultSetBox?

    init(connection: RuntimeJDBCConnectionBox, isPrepared: Bool, sqliteStatement: OpaquePointer? = nil) {
        self.connection = connection
        self.isPrepared = isPrepared
        self.sqliteStatement = sqliteStatement
    }
}

private final class RuntimeJDBCResultSetBox {
    let statement: RuntimeJDBCStatementBox
    let sqliteStatement: OpaquePointer
    let ownsStatement: Bool
    var isClosed = false
    var hasCurrentRow = false

    init(statement: RuntimeJDBCStatementBox, sqliteStatement: OpaquePointer, ownsStatement: Bool) {
        self.statement = statement
        self.sqliteStatement = sqliteStatement
        self.ownsStatement = ownsStatement
    }
}

private final class RuntimeSQLExceptionBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "java.sql.SQLException"
    }

    override var exceptionHierarchyFQNames: [String] {
        ["java.sql.SQLException", "kotlin.Exception", "kotlin.Throwable"]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("SQLException", message)
    }
}

private func runtimeAllocateSQLException(message: String?) -> Int {
    registerRuntimeObject(RuntimeSQLExceptionBox(message: message))
}

private func runtimeJDBCSetError(_ message: String, _ outThrown: UnsafeMutablePointer<Int>?) {
    outThrown?.pointee = runtimeAllocateSQLException(message: message)
}

private func runtimeJDBCString(_ raw: Int) -> String? {
    extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
}

private func runtimeJDBCConnection(_ raw: Int) -> RuntimeJDBCConnectionBox? {
    guard raw != 0, raw != runtimeNullSentinelInt,
          let pointer = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }
    return tryCast(pointer, to: RuntimeJDBCConnectionBox.self)
}

private func runtimeJDBCStatement(_ raw: Int) -> RuntimeJDBCStatementBox? {
    guard raw != 0, raw != runtimeNullSentinelInt,
          let pointer = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }
    return tryCast(pointer, to: RuntimeJDBCStatementBox.self)
}

private func runtimeJDBCResultSet(_ raw: Int) -> RuntimeJDBCResultSetBox? {
    guard raw != 0, raw != runtimeNullSentinelInt,
          let pointer = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }
    return tryCast(pointer, to: RuntimeJDBCResultSetBox.self)
}

private func runtimeJDBCErrorMessage(_ database: OpaquePointer?, fallback: String) -> String {
    guard let database, let message = sqlite3_errmsg(database) else {
        return fallback
    }
    return String(cString: message)
}

private func runtimeJDBCCloseResultSet(_ resultSet: RuntimeJDBCResultSetBox) {
    guard !resultSet.isClosed else { return }
    resultSet.isClosed = true
    if resultSet.ownsStatement {
        _ = sqlite3_finalize(resultSet.sqliteStatement)
    } else {
        _ = sqlite3_reset(resultSet.sqliteStatement)
    }
    if resultSet.statement.resultSet === resultSet {
        resultSet.statement.resultSet = nil
    }
}

private func runtimeJDBCCloseStatement(_ statement: RuntimeJDBCStatementBox) {
    guard !statement.isClosed else { return }
    if let resultSet = statement.resultSet {
        runtimeJDBCCloseResultSet(resultSet)
    }
    if statement.isPrepared, let sqliteStatement = statement.sqliteStatement {
        _ = sqlite3_finalize(sqliteStatement)
        statement.sqliteStatement = nil
    }
    statement.isClosed = true
}

private func runtimeJDBCCheckStatement(
    _ raw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> RuntimeJDBCStatementBox? {
    guard let statement = runtimeJDBCStatement(raw), !statement.isClosed,
          let connection = statement.connection, !connection.isClosed, connection.database != nil
    else {
        runtimeJDBCSetError("JDBC statement is closed or invalid", outThrown)
        return nil
    }
    return statement
}

private func runtimeJDBCPrepare(
    database: OpaquePointer,
    sql: String
) -> (result: Int32, statement: OpaquePointer?) {
    var sqliteStatement: OpaquePointer?
    let result = sql.withCString { sqlite3_prepare_v2(database, $0, -1, &sqliteStatement, nil) }
    return (result, sqliteStatement)
}

@_cdecl("__kk_jdbc_open")
public func kk_jdbc_open(_ urlRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let url = runtimeJDBCString(urlRaw), url.hasPrefix("jdbc:sqlite:") else {
        runtimeJDBCSetError("Only jdbc:sqlite: URLs are supported", outThrown)
        return 0
    }

    let path = String(url.dropFirst("jdbc:sqlite:".count))
    var database: OpaquePointer?
    let result = path.withCString { sqlite3_open($0, &database) }
    guard result == SQLITE_OK, let database else {
        let message = runtimeJDBCErrorMessage(database, fallback: "Unable to open SQLite database")
        if let database { _ = sqlite3_close_v2(database) }
        runtimeJDBCSetError(message, outThrown)
        return 0
    }
    return registerRuntimeObject(RuntimeJDBCConnectionBox(database: database))
}

@_cdecl("__kk_jdbc_connection_is_closed")
public func kk_jdbc_connection_is_closed(_ connectionRaw: Int) -> Int {
    guard let connection = runtimeJDBCConnection(connectionRaw) else { return 1 }
    return connection.isClosed ? 1 : 0
}

@_cdecl("__kk_jdbc_connection_create_statement")
public func kk_jdbc_connection_create_statement(
    _ connectionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let connection = runtimeJDBCConnection(connectionRaw),
          !connection.isClosed, connection.database != nil
    else {
        runtimeJDBCSetError("JDBC connection is closed or invalid", outThrown)
        return 0
    }
    let statement = RuntimeJDBCStatementBox(connection: connection, isPrepared: false)
    connection.statements.append(statement)
    return registerRuntimeObject(statement)
}

@_cdecl("__kk_jdbc_connection_prepare_statement")
public func kk_jdbc_connection_prepare_statement(
    _ connectionRaw: Int,
    _ sqlRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let connection = runtimeJDBCConnection(connectionRaw),
          !connection.isClosed, let database = connection.database
    else {
        runtimeJDBCSetError("JDBC connection is closed or invalid", outThrown)
        return 0
    }
    guard let sql = runtimeJDBCString(sqlRaw) else {
        runtimeJDBCSetError("Prepared statement SQL is invalid", outThrown)
        return 0
    }
    let prepared = runtimeJDBCPrepare(database: database, sql: sql)
    guard prepared.result == SQLITE_OK, let sqliteStatement = prepared.statement else {
        if let sqliteStatement = prepared.statement { _ = sqlite3_finalize(sqliteStatement) }
        runtimeJDBCSetError(runtimeJDBCErrorMessage(database, fallback: "Unable to prepare SQL"), outThrown)
        return 0
    }
    let statement = RuntimeJDBCStatementBox(
        connection: connection,
        isPrepared: true,
        sqliteStatement: sqliteStatement
    )
    connection.statements.append(statement)
    return registerRuntimeObject(statement)
}

@_cdecl("__kk_jdbc_connection_close")
public func kk_jdbc_connection_close(_ connectionRaw: Int) {
    guard let connection = runtimeJDBCConnection(connectionRaw), !connection.isClosed else { return }
    for statement in connection.statements {
        runtimeJDBCCloseStatement(statement)
    }
    connection.statements.removeAll()
    if let database = connection.database {
        _ = sqlite3_close_v2(database)
        connection.database = nil
    }
    connection.isClosed = true
}

@_cdecl("__kk_jdbc_statement_is_closed")
public func kk_jdbc_statement_is_closed(_ statementRaw: Int) -> Int {
    guard let statement = runtimeJDBCStatement(statementRaw) else { return 1 }
    return statement.isClosed || statement.connection?.isClosed != false ? 1 : 0
}

@_cdecl("__kk_jdbc_statement_execute_update")
public func kk_jdbc_statement_execute_update(
    _ statementRaw: Int,
    _ sqlRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let statement = runtimeJDBCCheckStatement(statementRaw, outThrown: outThrown),
          !statement.isPrepared, let database = statement.connection?.database
    else {
        if outThrown?.pointee == 0 { runtimeJDBCSetError("Statement is not a regular JDBC statement", outThrown) }
        return 0
    }
    guard let sql = runtimeJDBCString(sqlRaw) else {
        runtimeJDBCSetError("SQL is invalid", outThrown)
        return 0
    }
    if let resultSet = statement.resultSet { runtimeJDBCCloseResultSet(resultSet) }
    let prepared = runtimeJDBCPrepare(database: database, sql: sql)
    guard prepared.result == SQLITE_OK, let sqliteStatement = prepared.statement else {
        if let sqliteStatement = prepared.statement { _ = sqlite3_finalize(sqliteStatement) }
        runtimeJDBCSetError(runtimeJDBCErrorMessage(database, fallback: "Unable to prepare SQL"), outThrown)
        return 0
    }
    var result = sqlite3_step(sqliteStatement)
    while result == SQLITE_ROW {
        result = sqlite3_step(sqliteStatement)
    }
    _ = sqlite3_finalize(sqliteStatement)
    guard result == SQLITE_DONE else {
        runtimeJDBCSetError(runtimeJDBCErrorMessage(database, fallback: "Unable to execute SQL"), outThrown)
        return 0
    }
    return Int(sqlite3_changes(database))
}

@_cdecl("__kk_jdbc_statement_execute_query")
public func kk_jdbc_statement_execute_query(
    _ statementRaw: Int,
    _ sqlRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let statement = runtimeJDBCCheckStatement(statementRaw, outThrown: outThrown),
          !statement.isPrepared, let database = statement.connection?.database
    else {
        if outThrown?.pointee == 0 { runtimeJDBCSetError("Statement is not a regular JDBC statement", outThrown) }
        return 0
    }
    guard let sql = runtimeJDBCString(sqlRaw) else {
        runtimeJDBCSetError("SQL is invalid", outThrown)
        return 0
    }
    if let previousResult = statement.resultSet { runtimeJDBCCloseResultSet(previousResult) }
    let prepared = runtimeJDBCPrepare(database: database, sql: sql)
    guard prepared.result == SQLITE_OK, let sqliteStatement = prepared.statement else {
        if let sqliteStatement = prepared.statement { _ = sqlite3_finalize(sqliteStatement) }
        runtimeJDBCSetError(runtimeJDBCErrorMessage(database, fallback: "Unable to prepare query"), outThrown)
        return 0
    }
    let resultSet = RuntimeJDBCResultSetBox(
        statement: statement,
        sqliteStatement: sqliteStatement,
        ownsStatement: true
    )
    statement.resultSet = resultSet
    return registerRuntimeObject(resultSet)
}

@_cdecl("__kk_jdbc_statement_close")
public func kk_jdbc_statement_close(_ statementRaw: Int) {
    guard let statement = runtimeJDBCStatement(statementRaw) else { return }
    runtimeJDBCCloseStatement(statement)
}

@_cdecl("__kk_jdbc_prepared_statement_set_double")
public func kk_jdbc_prepared_statement_set_double(
    _ statementRaw: Int,
    _ parameterIndex: Int,
    _ valueBits: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) {
    outThrown?.pointee = 0
    guard let statement = runtimeJDBCCheckStatement(statementRaw, outThrown: outThrown),
          statement.isPrepared, let sqliteStatement = statement.sqliteStatement,
          let index = Int32(exactly: parameterIndex), parameterIndex >= 1
    else {
        if outThrown?.pointee == 0 { runtimeJDBCSetError("Prepared statement parameter index is invalid", outThrown) }
        return
    }
    if let resultSet = statement.resultSet { runtimeJDBCCloseResultSet(resultSet) }
    let value = Double(bitPattern: UInt64(bitPattern: Int64(valueBits)))
    let result = sqlite3_bind_double(sqliteStatement, index, value)
    if result != SQLITE_OK {
        runtimeJDBCSetError(runtimeJDBCErrorMessage(statement.connection?.database, fallback: "Unable to bind Double"), outThrown)
    }
}

@_cdecl("__kk_jdbc_prepared_statement_set_int")
public func kk_jdbc_prepared_statement_set_int(
    _ statementRaw: Int,
    _ parameterIndex: Int,
    _ value: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) {
    outThrown?.pointee = 0
    guard let statement = runtimeJDBCCheckStatement(statementRaw, outThrown: outThrown),
          statement.isPrepared, let sqliteStatement = statement.sqliteStatement,
          let index = Int32(exactly: parameterIndex), parameterIndex >= 1,
          let sqliteValue = Int32(exactly: value)
    else {
        if outThrown?.pointee == 0 { runtimeJDBCSetError("Prepared statement parameter index or Int value is invalid", outThrown) }
        return
    }
    if let resultSet = statement.resultSet { runtimeJDBCCloseResultSet(resultSet) }
    let result = sqlite3_bind_int(sqliteStatement, index, sqliteValue)
    if result != SQLITE_OK {
        runtimeJDBCSetError(runtimeJDBCErrorMessage(statement.connection?.database, fallback: "Unable to bind Int"), outThrown)
    }
}

@_cdecl("__kk_jdbc_prepared_statement_execute_update")
public func kk_jdbc_prepared_statement_execute_update(
    _ statementRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let statement = runtimeJDBCCheckStatement(statementRaw, outThrown: outThrown),
          statement.isPrepared, let database = statement.connection?.database,
          let sqliteStatement = statement.sqliteStatement
    else {
        if outThrown?.pointee == 0 { runtimeJDBCSetError("Prepared statement is invalid", outThrown) }
        return 0
    }
    if let resultSet = statement.resultSet { runtimeJDBCCloseResultSet(resultSet) }
    _ = sqlite3_reset(sqliteStatement)
    var result = sqlite3_step(sqliteStatement)
    while result == SQLITE_ROW {
        result = sqlite3_step(sqliteStatement)
    }
    guard result == SQLITE_DONE else {
        runtimeJDBCSetError(runtimeJDBCErrorMessage(database, fallback: "Unable to execute prepared SQL"), outThrown)
        return 0
    }
    return Int(sqlite3_changes(database))
}

@_cdecl("__kk_jdbc_prepared_statement_execute_query")
public func kk_jdbc_prepared_statement_execute_query(
    _ statementRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let statement = runtimeJDBCCheckStatement(statementRaw, outThrown: outThrown),
          statement.isPrepared, let sqliteStatement = statement.sqliteStatement
    else {
        if outThrown?.pointee == 0 { runtimeJDBCSetError("Prepared statement is invalid", outThrown) }
        return 0
    }
    if let previousResult = statement.resultSet { runtimeJDBCCloseResultSet(previousResult) }
    _ = sqlite3_reset(sqliteStatement)
    let resultSet = RuntimeJDBCResultSetBox(
        statement: statement,
        sqliteStatement: sqliteStatement,
        ownsStatement: false
    )
    statement.resultSet = resultSet
    return registerRuntimeObject(resultSet)
}

@_cdecl("__kk_jdbc_result_set_is_closed")
public func kk_jdbc_result_set_is_closed(_ resultSetRaw: Int) -> Int {
    guard let resultSet = runtimeJDBCResultSet(resultSetRaw) else { return 1 }
    return resultSet.isClosed || resultSet.statement.isClosed || resultSet.statement.connection?.isClosed != false ? 1 : 0
}

@_cdecl("__kk_jdbc_result_set_next")
public func kk_jdbc_result_set_next(
    _ resultSetRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let resultSet = runtimeJDBCResultSet(resultSetRaw), !resultSet.isClosed,
          !resultSet.statement.isClosed, let database = resultSet.statement.connection?.database
    else {
        runtimeJDBCSetError("JDBC result set is closed or invalid", outThrown)
        return 0
    }
    let result = sqlite3_step(resultSet.sqliteStatement)
    if result == SQLITE_ROW {
        resultSet.hasCurrentRow = true
        return 1
    }
    resultSet.hasCurrentRow = false
    if result == SQLITE_DONE { return 0 }
    runtimeJDBCSetError(runtimeJDBCErrorMessage(database, fallback: "Unable to advance result set"), outThrown)
    return 0
}

private func runtimeJDBCColumn(
    _ raw: Int,
    columnIndex: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> (resultSet: RuntimeJDBCResultSetBox, index: Int32)? {
    guard let resultSet = runtimeJDBCResultSet(raw), !resultSet.isClosed,
          !resultSet.statement.isClosed, resultSet.hasCurrentRow,
          let index = Int32(exactly: columnIndex), columnIndex >= 1
    else {
        runtimeJDBCSetError("JDBC result set column index or cursor is invalid", outThrown)
        return nil
    }
    return (resultSet, index - 1)
}

@_cdecl("__kk_jdbc_result_set_get_int")
public func kk_jdbc_result_set_get_int(
    _ resultSetRaw: Int,
    _ columnIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let column = runtimeJDBCColumn(resultSetRaw, columnIndex: columnIndex, outThrown: outThrown) else { return 0 }
    return Int(sqlite3_column_int(column.resultSet.sqliteStatement, column.index))
}

@_cdecl("__kk_jdbc_result_set_get_string")
public func kk_jdbc_result_set_get_string(
    _ resultSetRaw: Int,
    _ columnIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let column = runtimeJDBCColumn(resultSetRaw, columnIndex: columnIndex, outThrown: outThrown) else { return 0 }
    guard let text = sqlite3_column_text(column.resultSet.sqliteStatement, column.index) else {
        return runtimeMakeStringRaw("")
    }
    let cString = UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self)
    return runtimeMakeStringRaw(String(cString: cString))
}

@_cdecl("__kk_jdbc_result_set_get_double")
public func kk_jdbc_result_set_get_double(
    _ resultSetRaw: Int,
    _ columnIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let column = runtimeJDBCColumn(resultSetRaw, columnIndex: columnIndex, outThrown: outThrown) else { return 0 }
    let value = sqlite3_column_double(column.resultSet.sqliteStatement, column.index)
    return Int(bitPattern: UInt(value.bitPattern))
}

@_cdecl("__kk_jdbc_result_set_close")
public func kk_jdbc_result_set_close(_ resultSetRaw: Int) {
    guard let resultSet = runtimeJDBCResultSet(resultSetRaw) else { return }
    runtimeJDBCCloseResultSet(resultSet)
}

@_cdecl("__kk_jdbc_sql_exception_new")
public func kk_jdbc_sql_exception_new() -> Int {
    runtimeAllocateSQLException(message: nil)
}

@_cdecl("__kk_jdbc_sql_exception_new_message")
public func kk_jdbc_sql_exception_new_message(_ messageRaw: Int) -> Int {
    runtimeAllocateSQLException(message: runtimeJDBCString(messageRaw))
}
