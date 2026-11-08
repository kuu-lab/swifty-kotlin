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
    public companion object {
        public const val TYPE_FORWARD_ONLY: Int = 1003
        public const val TYPE_SCROLL_INSENSITIVE: Int = 1004
        public const val TYPE_SCROLL_SENSITIVE: Int = 1005
        public const val CONCUR_READ_ONLY: Int = 1007
        public const val CONCUR_UPDATABLE: Int = 1008
        public const val HOLD_CURSORS_OVER_COMMIT: Int = 1
        public const val CLOSE_CURSORS_AT_COMMIT: Int = 2
        public const val FETCH_FORWARD: Int = 1000
        public const val FETCH_REVERSE: Int = 1001
        public const val FETCH_UNKNOWN: Int = 1002
    }

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

/** JDBC column-type codes, mirroring `java.sql.Types`. */
public object Types {
    public const val BIT: Int = -7
    public const val TINYINT: Int = -6
    public const val SMALLINT: Int = 5
    public const val INTEGER: Int = 4
    public const val BIGINT: Int = -5
    public const val FLOAT: Int = 6
    public const val REAL: Int = 7
    public const val DOUBLE: Int = 8
    public const val NUMERIC: Int = 2
    public const val DECIMAL: Int = 3
    public const val CHAR: Int = 1
    public const val VARCHAR: Int = 12
    public const val LONGVARCHAR: Int = -1
    public const val BOOLEAN: Int = 16
    public const val BINARY: Int = -2
    public const val VARBINARY: Int = -3
    public const val LONGVARBINARY: Int = -4
    public const val DATE: Int = 91
    public const val TIME: Int = 92
    public const val TIMESTAMP: Int = 93
    public const val TIME_WITH_TIMEZONE: Int = 2013
    public const val TIMESTAMP_WITH_TIMEZONE: Int = 2014
    public const val NULL: Int = 0
    public const val OTHER: Int = 1111
    public const val JAVA_OBJECT: Int = 2000
    public const val DISTINCT: Int = 2001
    public const val STRUCT: Int = 2002
    public const val ARRAY: Int = 2003
    public const val BLOB: Int = 2004
    public const val CLOB: Int = 2005
    public const val REF: Int = 2006
    public const val DATALINK: Int = 70
    public const val ROWID: Int = -8
    public const val NCHAR: Int = -15
    public const val NVARCHAR: Int = -9
    public const val LONGNVARCHAR: Int = -16
    public const val NCLOB: Int = 2011
    public const val SQLXML: Int = 2009
    public const val REF_CURSOR: Int = 2012
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
