require "java"
java_import "java.sql.DriverManager"
java_import "org.apache.commons.lang.StringEscapeUtils"

module IsolatedServer
  class Mysql < Base
    class WrappedJDBCConnection
      def initialize(port)
        @cx ||= DriverManager.get_connection("jdbc:mysql://127.0.0.1:#{port}/mysql", "root", "")
      end

      def query(sql)
        stmt = @cx.create_statement
        if sql !~ /^select/i && sql !~ /^show/i
          return stmt.execute(sql)
        end

        rs = stmt.execute_query(sql)

        rows = []
        while (rs.next)
          meta_data = rs.get_meta_data
          num_cols = meta_data.get_column_count

          row = {}
          1.upto(num_cols) do |col|
            col_name = meta_data.get_column_label(col)
            col_value = rs.get_object(col) # of meta_data.get_column_type(col)

            row[col_name] = col_value
          end

          rows << row
        end
        rows
      ensure
        stmt.close if stmt
        rs.close if rs
      end

      def escape(str)
        StringEscapeUtils.escapeSql(str)
      end
    end

    module DBConnection
      def connection
        @cx ||= WrappedJDBCConnection.new(@port)
      end
    end
  end
end
