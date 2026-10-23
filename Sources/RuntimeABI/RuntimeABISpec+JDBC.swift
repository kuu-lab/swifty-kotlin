private let abi = RuntimeABISectionBuilder("JDBC")
private let abiException = RuntimeABISectionBuilder("Exception")

public extension RuntimeABISpec {
    static let jdbcFunctions: [RuntimeABIFunctionSpec] = [
        abi.th("__kk_jdbc_open", "urlRaw outThrown"),
        abi.nt("__kk_jdbc_connection_is_closed", "connectionRaw", raw: true),
        abi.th("__kk_jdbc_connection_create_statement", "connectionRaw outThrown"),
        abi.th("__kk_jdbc_connection_prepare_statement", "connectionRaw sqlRaw outThrown"),
        abi.nt("__kk_jdbc_connection_close", "connectionRaw", ret: .void),
        abi.nt("__kk_jdbc_statement_is_closed", "statementRaw", raw: true),
        abi.th("__kk_jdbc_statement_execute_update", "statementRaw sqlRaw outThrown"),
        abi.th("__kk_jdbc_statement_execute_query", "statementRaw sqlRaw outThrown"),
        abi.nt("__kk_jdbc_statement_close", "statementRaw", ret: .void),
        abi.th("__kk_jdbc_prepared_statement_set_double", "statementRaw parameterIndex value outThrown", ret: .void),
        abi.th("__kk_jdbc_prepared_statement_set_int", "statementRaw parameterIndex value outThrown", ret: .void),
        abi.th("__kk_jdbc_prepared_statement_execute_update", "statementRaw outThrown"),
        abi.th("__kk_jdbc_prepared_statement_execute_query", "statementRaw outThrown"),
        abi.nt("__kk_jdbc_result_set_is_closed", "resultSetRaw", raw: true),
        abi.th("__kk_jdbc_result_set_next", "resultSetRaw outThrown", raw: true),
        abi.th("__kk_jdbc_result_set_get_int", "resultSetRaw columnIndex outThrown"),
        abi.th("__kk_jdbc_result_set_get_string", "resultSetRaw columnIndex outThrown"),
        abi.th("__kk_jdbc_result_set_get_double", "resultSetRaw columnIndex outThrown"),
        abi.nt("__kk_jdbc_result_set_close", "resultSetRaw", ret: .void),
        abiException.nt("__kk_jdbc_sql_exception_new"),
        abiException.nt("__kk_jdbc_sql_exception_new_message", "messageRaw"),
    ]
}
