pgpool-ha 3.x
=============

pgpool-ha is an OCF style Resource Agent for pgpool-II.

install
-------

 $ su 
 # install -m 0755 -o root -g root \
     ./pgpool.in  /usr/lib/ocf/resource.d/heartbeat/pgpool


usage
-----

OCF parameters are as below.

### pgpoolconf

Specifies the path of pgpool.conf. (default: /usr/local/etc/pgpool.conf)

### pcpconf

Specifies the path of pcp.conf. (default: empty)

### hbaconf

Specifies the path of pool_hba.conf. (default: empty)

### logfile

Specifies the log output. (default: empty)

You can set a file path for redirection or a program for pipeline processing.
The value start with "|" is recognized as a program.
Parameter "-n" is added to pgpool implicitly if some value is set into this.
The example are as follows:

     "/var/log/pgpool.log"
     "| logger -t pgpool -p local3.info"

### options

Specifies pgpool's starting options. (default: empty)

"-D" is recommended if pgpool_status file is not in shared space.
"-n", "-f", "-a" and "-F" shouldn't be included, since these are
used implicitly by other parameters.

### pgpooluser

Specifies the user to run the pgpool process. (default: postgres)

### checkmethod

Specifies monitoring method. (default: pid)

Possible values are as follows:

     "pid"    check by process existence.
     "pcp"    check by pcp_node_count command.
     "psql"   check by psql or pg_isready command.

### checkstring

Specifies the details for the monitoring method.
This parameter means differently by checkmethod setting.

When checkmetod is "pid", this means pid file path.
The default value is pid_file_name setting in pgpool.conf.

When checkmetod is "pcp", this means parameters for pcp_nod_count command.
The default value is "10 localhost 9898 postgres pass".
"-w -h localhost -p 9898" is a good idea for 3.5.x and later version,
for the response 'authentication failed' is considered success.

When checkmetod is "psql", this means parameters for psql or other command
which is specified in psqlcmd parameter.
The default value is "-U postgres -h localhost -l -p 9999".
"-U postgres -h localhost -p 9999" is a good idea when you use pg_isready.

### psqlcmd

Specifies the path of psql or pg_isready command.

### pgpoolcmd

Specifies the path of pgpool command.

### pcpnccmd

Specifies the path of pcp_node_count command.


crm samples
-----------

simple process check:

    primitive pgpool ocf:heartbeat:pgpool \
      params pgpoolconf="/usr/local/pgpool/etc/pgpool.conf" \
           options="-D"  pgpooluser="postgres" \
           checkmethod="pid" \
           pgpoolcmd="/usr/local/pgpool/bin/pgpool" \
      op start   interval=0s  timeout=60s \
      op monitor interval=10s timeout=30s \
      op stop    interval=0s  timeout=60s


using pgpool-II 3.5.x's pcp_node_count:

    primitive pgpool ocf:heartbeat:pgpool \
      params pgpoolconf="/usr/pgpool2-3.5/etc/pgpool.conf" \
           pcpconf="/usr/pgpool2-3.5/etc/pcp.conf" \
           options="-D"  pgpooluser="postgres" \
           checkmethod="pcp" checkstring="-w -h localhost -p 9898" \
           pgpoolcmd="/usr/pgpool2-3.5/bin/pgpool" \
           pcpnccmd="/usr/pgpool2-3.5/bin/pcp_node_count" \
      op start   interval=0s  timeout=60s \
      op monitor interval=30s timeout=30s \
      op stop    interval=0s  timeout=60s


using pg_isready:

    primitive pgpool pgpool \
      params pgpoolconf="/etc/pgpool-II-95/pgpool.conf" \
          pcpconf="/etc/pgpool-II-95/pcp.conf" \
          options="-D" pgpooluser="postgres" \
          checkmethod="psql" checkstring="-U postgres -h localhost -p 9999" \
          pgpoolcmd="/usr/pgpool-9.5/bin/pgpool" \
          psqlcmd="/usr/pgsql-9.5/bin/pg_isready" \
      op start   interval=0s  timeout=60s \
      op monitor interval=30s timeout=30s \
      op stop    interval=0s  timeout=60s


support ML
----------

 pgpool-general@pgpool.net



