public extension RuntimeABISpec {
    static let jdbcFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_open",
            parameters: [
                RuntimeABIParameter(name: "urlRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "JDBC"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_connection_is_closed",
            parameters: [RuntimeABIParameter(name: "connectionRaw", type: .intptr)],
            returnType: .intptr,
            section: "JDBC",
            isThrowing: false,
            returnsRawBoolean: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_connection_create_statement",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "JDBC"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_connection_prepare_statement",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
                RuntimeABIParameter(name: "sqlRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "JDBC"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_connection_close",
            parameters: [RuntimeABIParameter(name: "connectionRaw", type: .intptr)],
            returnType: .void,
            section: "JDBC",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_statement_is_closed",
            parameters: [RuntimeABIParameter(name: "statementRaw", type: .intptr)],
            returnType: .intptr,
            section: "JDBC",
            isThrowing: false,
            returnsRawBoolean: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_statement_execute_update",
            parameters: [
                RuntimeABIParameter(name: "statementRaw", type: .intptr),
                RuntimeABIParameter(name: "sqlRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "JDBC"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_statement_execute_query",
            parameters: [
                RuntimeABIParameter(name: "statementRaw", type: .intptr),
                RuntimeABIParameter(name: "sqlRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "JDBC"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_statement_close",
            parameters: [RuntimeABIParameter(name: "statementRaw", type: .intptr)],
            returnType: .void,
            section: "JDBC",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_prepared_statement_set_double",
            parameters: [
                RuntimeABIParameter(name: "statementRaw", type: .intptr),
                RuntimeABIParameter(name: "parameterIndex", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .void,
            section: "JDBC"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_prepared_statement_set_int",
            parameters: [
                RuntimeABIParameter(name: "statementRaw", type: .intptr),
                RuntimeABIParameter(name: "parameterIndex", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .void,
            section: "JDBC"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_prepared_statement_execute_update",
            parameters: [
                RuntimeABIParameter(name: "statementRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "JDBC"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_prepared_statement_execute_query",
            parameters: [
                RuntimeABIParameter(name: "statementRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "JDBC"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_result_set_is_closed",
            parameters: [RuntimeABIParameter(name: "resultSetRaw", type: .intptr)],
            returnType: .intptr,
            section: "JDBC",
            isThrowing: false,
            returnsRawBoolean: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_result_set_next",
            parameters: [
                RuntimeABIParameter(name: "resultSetRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "JDBC",
            returnsRawBoolean: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_result_set_get_int",
            parameters: [
                RuntimeABIParameter(name: "resultSetRaw", type: .intptr),
                RuntimeABIParameter(name: "columnIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "JDBC"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_result_set_get_string",
            parameters: [
                RuntimeABIParameter(name: "resultSetRaw", type: .intptr),
                RuntimeABIParameter(name: "columnIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "JDBC"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_result_set_get_double",
            parameters: [
                RuntimeABIParameter(name: "resultSetRaw", type: .intptr),
                RuntimeABIParameter(name: "columnIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "JDBC"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_result_set_close",
            parameters: [RuntimeABIParameter(name: "resultSetRaw", type: .intptr)],
            returnType: .void,
            section: "JDBC",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_sql_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_jdbc_sql_exception_new_message",
            parameters: [RuntimeABIParameter(name: "messageRaw", type: .intptr)],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
    ]
}
