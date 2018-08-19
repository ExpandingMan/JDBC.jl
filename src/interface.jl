
mutable struct Connection <: DBAPI.AbstractConnection
    conn::Union{JConnection,Nothing}

    Connection(conn::JConnection) = new(conn)
end


struct JDBCError <: DBAPI.AbstractDBError
    msg::AbstractString
end


mutable struct Cursor <: DBAPI.AbstractCursor
    conn::Connection
    stmt::Union{JStatement, Nothing}
    rs::Union{JResultSet, Nothing}

    Cursor(conn::Connection, stmt::JStatement) = new(conn, stmt, nothing)
end

function Cursor(conn::Connection)
    isopen(conn) || throw(JDBCError("Attempting to create cursor with a null connection"))
    Cursor(conn, createstatement(conn))
end


# TODO these mainly for compatibility
const JDBCCursor = Cursor
const JDBCConnection = Connection
export JDBCError, JDBCConnection, JDBCCursor


"""
Open a JDBC Connection to the specified `host`.  The username and password can be optionally passed
 as a Dictionary `props` of the form `Dict("user" => "username", "passwd" => "password")`.
  The JDBC connector location can be optionally passed as `connectorpath`, if it is not
 added to the java class path.

Returns a `JDBCConnection` instance.
"""
function Connection(host::AbstractString; props=Dict(), connectorpath="")
    if !JavaCall.isloaded()
        !isempty(connectorpath) && JavaCall.addClassPath(connectorpath)
        JDBC.init()
    end
    conn = if !isempty(props)
        DriverManager.getConnection(host, props)
    else
        DriverManager.getConnection(host)
    end
    Connection(conn)
end

createstatement(conn::Connection) = createStatement(conn.conn)

"""
Closes the JDBCConnection `conn`.  Throws a `JDBCError` if connection is null.

Returns `nothing`.
"""
function Base.close(conn::Connection)
    isopen(conn) || throw(JDBCError("Cannot close null connection."))
    close(conn.conn)
    conn.conn = nothing
end

"""
Returns a boolean indicating whether connection `conn` is open.
"""
Base.isopen(conn::Connection) = (conn.conn ≠ nothing)

"""
Commit any pending transaction to the database.  Throws a `JDBCError` if connection is null.

Returns `nothing`.
"""
function DBAPI.commit(conn::Connection)
    isopen(conn) || throw(JDBCError("Commit called on null connection."))
    commit(conn.conn)
    nothing
end

"""
Roll back to the start of any pending transaction.  Throws a `JDBCError` if connection is null.

Returns `nothing`.
"""
function DBAPI.rollback!(conn::Connection)
    isopen(conn) || throw(JDBCError("Rollback called on null connection."))
    rollback(conn.conn)
    nothing
end

"""
Create a new database cursor.

Returns a `JDBCCursor` instance.
"""
DBAPI.cursor(conn::Connection) = Cursor(conn)

function Cursor(host::AbstractString; props=Dict(), connectorpath="")
    cursor(Connection(host, props=props, connectorpath=connectorpath))
end

"""
Return the corresponding connection for a given cursor.
"""
DBAPI.connection(csr::Cursor) = csr.conn

"""
Run a query on a database.

The results of the query are not returned by this function but are accessible
through the cursor.

`parameters` can be any iterable of positional parameters, or of some
T<:AbstractDict for keyword/named parameters.

Throws a `JDBCError` if query caused an error, cursor is not initialized or
 connection is null.

Returns `nothing`.
"""
function DBAPI.execute!(csr::Cursor, qry::AbstractString)
    isopen(connection(csr)) || throw(JDBCError("Cannot execute with null connection."))
    csr.stmt == nothing && throw(JDBCError("Execute called on uninitialized cursor."))
    exectype = execute(csr.stmt, qry)
    try
        JavaCall.geterror()
    catch err
        throw(JDBCError(err.msg))
    end
    if exectype == 1  # if this is a statement that returned a result set.
        csr.rs = getResultSet(csr.stmt)
    else
        csr.rs = nothing
    end
    nothing
end

"""
Create a row iterator.

This method returns an instance of an iterator type which returns one row
on each iteration. Each row returnes a Tuple{...}.

Throws a `JDBCError` if `execute!` was not called on the cursor or connection is null.

Returns a `JDBCRowIterator` instance.
"""
function rows(csr::Cursor)
    isopen(connection(csr)) || throw(JDBCError("Cannot create iterator with null connection."))
    if csr.rs == nothing
        throw(JDBCError(string("Cannot create iterator with null result set.  ",
                               "Please call execute! on the cursor first.")))
    end
    JDBCRowIterator(csr.rs)
end

export rows
