#--
# =============================================================================
# Copyright (c) 2004, Jamis Buck (jgb3@email.byu.edu)
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
# 
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
# 
#     * The names of its contributors may not be used to endorse or promote
#       products derived from this software without specific prior written
#       permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# =============================================================================
#++

require 'sqlite3/errors'
require 'sqlite3/resultset'

class String
  def to_blob
    SQLite3::Blob.new( self )
  end
end

module SQLite3

  # A class for differentiating between strings and blobs, when binding them
  # into statements.
  class Blob < String; end

  # A statement represents a prepared-but-unexecuted SQL query. It will rarely
  # (if ever) be instantiated directly by a client, and is most often obtained
  # via the Database#prepare method.
  class Statement

    # This is any text that followed the first valid SQL statement in the text
    # with which the statement was initialized. If there was no trailing text,
    # this will be the empty string.
    attr_reader :remainder

    # The underlying opaque handle used to access the SQLite @driver.
    attr_reader :handle

    # Create a new statement attached to the given Database instance, and which
    # encapsulates the given SQL text. If the text contains more than one
    # statement (i.e., separated by semicolons), then the #remainder property
    # will be set to the trailing text.
    def initialize( db, sql, utf16=false )
      @db = db
      @driver = @db.driver
      @closed = false
      result, @handle, @remainder = @driver.prepare( @db.handle, sql )
      Error.check( result, @db )
    end

    # Closes the statement by finalizing the underlying statement
    # handle. The statement must not be used after being closed.
    def close
      must_be_open!
      @closed = true
      @driver.finalize( @handle )
    end

    # Returns true if the underlying statement has been closed.
    def closed?
      @closed
    end

    # Binds the given variables to the corresponding placeholders in the SQL
    # text.
    #
    # See Database#execute for a description of the valid placeholder
    # syntaxes.
    #
    # Example:
    #
    #   stmt = db.prepare( "select * from table where a=? and b=?" )
    #   stmt.bind_params( 15, "hello" )
    #
    # See also #execute, #bind_param, Statement#bind_param, and
    # Statement#bind_params.
    def bind_params( *bind_vars )
      index = 1
      bind_vars.flatten.each do |var|
        if Hash === var
          var.each { |key, val| bind_param key, val }
        else
          bind_param index, var
          index += 1
        end
      end
    end

    # Binds value to the named (or positional) placeholder. If +param+ is a
    # Fixnum, it is treated as an index for a positional placeholder.
    # Otherwise it is used as the name of the placeholder to bind to.
    #
    # See also #bind_params.
    def bind_param( param, value )
      must_be_open!
      if Fixnum === param
        case value
          when Integer then
            @driver.bind_int( @handle, param, value )
          when Numeric then
            @driver.bind_double( @handle, param, value.to_f )
          when Blob then
            @driver.bind_blob( @handle, param, value )
          when nil then
            @driver.bind_null( @handle, param )
          else
            @driver.bind_text( @handle, param, value )
        end
      else
        index = @driver.bind_parameter_index(
          @handle, param.to_s )
        raise Exception, "no such bind parameter '#{param}'" if index == 0
        bind_param index, value
      end
    end

    # Execute the statement. This creates a new ResultSet object for the
    # statement's virtual machine. If a block was given, the new ResultSet will
    # be yielded to it; otherwise, the ResultSet will be returned.
    #
    # Any parameters will be bound to the statement using #bind_params.
    #
    # Example:
    #
    #   stmt = db.prepare( "select * from table" )
    #   stmt.execute do |result|
    #     ...
    #   end
    #
    # See also #bind_params, #execute!.
    def execute( *bind_vars )
      must_be_open!
      @driver.reset( @handle ) if @results

      bind_params *bind_vars unless bind_vars.empty?
      @results = ResultSet.new( @db, self )

      if block_given?
        yield @results
      else
        return @results
      end
    end

    # Execute the statement. If no block was given, this returns an array of
    # rows returned by executing the statement. Otherwise, each row will be
    # yielded to the block.
    #
    # Any parameters will be bound to the statement using #bind_params.
    #
    # Example:
    #
    #   stmt = db.prepare( "select * from table" )
    #   stmt.execute! do |row|
    #     ...
    #   end
    #
    # See also #bind_params, #execute.
    def execute!( *bind_vars )
      result = execute( *bind_vars )
      rows = [] unless block_given?
      while row = result.next
        if block_given?
          yield row
        else
          rows << row
        end
      end
      rows
    end

    # Return an array of the column names for this statement. Note that this
    # may execute the statement in order to obtain the metadata; this makes it
    # a (potentially) expensive operation.
    def columns
      get_metadata unless @columns
      return @columns
    end

    # Return an array of the data types for each column in this statement. Note
    # that this may execute the statement in order to obtain the metadata; this
    # makes it a (potentially) expensive operation.
    def types
      get_metadata unless @types
      return @types
    end

    # A convenience method for obtaining the metadata about the query. Note
    # that this will actually execute the SQL, which means it can be a
    # (potentially) expensive operation.
    def get_metadata
      must_be_open!

      @columns = []
      @types = []

      column_count = @driver.column_count( @handle )
      column_count.times do |column|
        @columns << @driver.column_name( @handle, column )
        @types << @driver.column_decltype( @handle, column )
      end

      @columns.freeze
      @types.freeze
    end
    private :get_metadata

    # Performs a sanity check to ensure that the statement is not
    # closed. If it is, an exception is raised.
    def must_be_open! # :nodoc:
      if @closed
        raise SQLite3::Exception, "cannot use a closed statement"
      end
    end

  end

end
