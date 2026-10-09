package java.sql

import kotlin.Exception
import kotlin.internal.KsSymbolName

public object DriverManager {
    public fun getConnection(url: String): Connection = Connection(jdbcOpen(url))
}

public class Connection internal constructor(private val rawHandle: Long) : AutoCloseable {
    public val isClosed: Boolean
        get() = jdbcConnectionIsClosed(rawHandle)

    public fun isClosed(): Boolean = jdbcConnectionIsClosed(rawHandle)

    public fun createStatement(): Statement = Statement(jdbcConnectionCreateStatement(rawHandle))

    public fun prepareStatement(sql: String): PreparedStatement =
        PreparedStatement(jdbcConnectionPrepareStatement(rawHandle, sql))

    override fun close() {
        jdbcConnectionClose(rawHandle)
    }
}

public open class Statement internal constructor(protected val rawHandle: Long) : AutoCloseable {
    public val isClosed: Boolean
        get() = jdbcStatementIsClosed(rawHandle)

    public fun isClosed(): Boolean = jdbcStatementIsClosed(rawHandle)

    public fun executeUpdate(sql: String): Int = jdbcStatementExecuteUpdate(rawHandle, sql)

    public fun executeQuery(sql: String): ResultSet = ResultSet(jdbcStatementExecuteQuery(rawHandle, sql))

    override fun close() {
        jdbcStatementClose(rawHandle)
    }
}

public class PreparedStatement internal constructor(rawHandle: Long) : Statement(rawHandle) {
    public fun setDouble(parameterIndex: Int, value: Double) {
        jdbcPreparedStatementSetDouble(rawHandle, parameterIndex, value)
    }

    public fun setInt(parameterIndex: Int, value: Int) {
        jdbcPreparedStatementSetInt(rawHandle, parameterIndex, value)
    }

    public fun executeUpdate(): Int = jdbcPreparedStatementExecuteUpdate(rawHandle)

    public fun executeQuery(): ResultSet = ResultSet(jdbcPreparedStatementExecuteQuery(rawHandle))
}

public class ResultSet internal constructor(private val rawHandle: Long) : AutoCloseable {
    public val isClosed: Boolean
        get() = jdbcResultSetIsClosed(rawHandle)

    public fun isClosed(): Boolean = jdbcResultSetIsClosed(rawHandle)

    public fun next(): Boolean = jdbcResultSetNext(rawHandle)

    public fun getInt(columnIndex: Int): Int = jdbcResultSetGetInt(rawHandle, columnIndex)

    public fun getString(columnIndex: Int): String = jdbcResultSetGetString(rawHandle, columnIndex)

    public fun getDouble(columnIndex: Int): Double = jdbcResultSetGetDouble(rawHandle, columnIndex)

    override fun close() {
        jdbcResultSetClose(rawHandle)
    }
}

public class SQLException : Exception {
    @KsSymbolName("__kk_jdbc_sql_exception_new")
    public constructor()

    @KsSymbolName("__kk_jdbc_sql_exception_new_message")
    public constructor(message: String?)
}

@KsSymbolName("__kk_jdbc_open")
private external fun jdbcOpen(url: String): Long

@KsSymbolName("__kk_jdbc_connection_is_closed")
private external fun jdbcConnectionIsClosed(connectionRaw: Long): Boolean

@KsSymbolName("__kk_jdbc_connection_create_statement")
private external fun jdbcConnectionCreateStatement(connectionRaw: Long): Long

@KsSymbolName("__kk_jdbc_connection_prepare_statement")
private external fun jdbcConnectionPrepareStatement(connectionRaw: Long, sql: String): Long

@KsSymbolName("__kk_jdbc_connection_close")
private external fun jdbcConnectionClose(connectionRaw: Long)

@KsSymbolName("__kk_jdbc_statement_is_closed")
private external fun jdbcStatementIsClosed(statementRaw: Long): Boolean

@KsSymbolName("__kk_jdbc_statement_execute_update")
private external fun jdbcStatementExecuteUpdate(statementRaw: Long, sql: String): Int

@KsSymbolName("__kk_jdbc_statement_execute_query")
private external fun jdbcStatementExecuteQuery(statementRaw: Long, sql: String): Long

@KsSymbolName("__kk_jdbc_statement_close")
private external fun jdbcStatementClose(statementRaw: Long)

@KsSymbolName("__kk_jdbc_prepared_statement_set_double")
private external fun jdbcPreparedStatementSetDouble(statementRaw: Long, parameterIndex: Int, value: Double)

@KsSymbolName("__kk_jdbc_prepared_statement_set_int")
private external fun jdbcPreparedStatementSetInt(statementRaw: Long, parameterIndex: Int, value: Int)

@KsSymbolName("__kk_jdbc_prepared_statement_execute_update")
private external fun jdbcPreparedStatementExecuteUpdate(statementRaw: Long): Int

@KsSymbolName("__kk_jdbc_prepared_statement_execute_query")
private external fun jdbcPreparedStatementExecuteQuery(statementRaw: Long): Long

@KsSymbolName("__kk_jdbc_result_set_is_closed")
private external fun jdbcResultSetIsClosed(resultSetRaw: Long): Boolean

@KsSymbolName("__kk_jdbc_result_set_next")
private external fun jdbcResultSetNext(resultSetRaw: Long): Boolean

@KsSymbolName("__kk_jdbc_result_set_get_int")
private external fun jdbcResultSetGetInt(resultSetRaw: Long, columnIndex: Int): Int

@KsSymbolName("__kk_jdbc_result_set_get_string")
private external fun jdbcResultSetGetString(resultSetRaw: Long, columnIndex: Int): String

@KsSymbolName("__kk_jdbc_result_set_get_double")
private external fun jdbcResultSetGetDouble(resultSetRaw: Long, columnIndex: Int): Double

@KsSymbolName("__kk_jdbc_result_set_close")
private external fun jdbcResultSetClose(resultSetRaw: Long)
