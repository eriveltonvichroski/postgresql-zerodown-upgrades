#!/bin/bash

PG01="172.28.33.11"
PG02="172.28.33.12"
PG03="172.28.33.13"
NODE1="pg01"
NODE2="pg02"
NODE3="pg03"
VIP_PG="172.28.33.10"
VIP_REPLICATION="10.2.2.10"
ETH_REPLIC="eth2"
VIP_PGBOURCER="172.28.33.9"
ETH_PGBOUNCER="eth1"
ETH_PG="eth1"
NODES=("pg01" "pg02" "pg03")

POSTGRESQL_VERSION=10
PG_BIN=/usr/pgsql-${POSTGRESQL_VERSION}
PGDATA_BASE=/bd/postgres/${POSTGRESQL_VERSION}/pgsql
PGDATA=$PGDATA_BASE/data
PG_CONF_EXT=/etc/postgresql/${POSTGRESQL_VERSION}
PKG=yum
PGPOOL_DIR=/etc/pgpool-II-10
PGPOOL_PKG=pgpool-II-10


function setup_ssh_keys() {
echo "
# This file controls the state of SELinux on the system.
# SELINUX= can take one of these three values:
#       enforcing - SELinux security policy is enforced.
#       permissive - SELinux prints warnings instead of enforcing.
#       disabled - SELinux is fully disabled.
SELINUX=disabled
# SELINUXTYPE= type of policy in use. Possible values are:
#       targeted - Only targeted network daemons are protected.
#       strict - Full SELinux protection.
SELINUXTYPE=targeted

# SETLOCALDEFS= Check local definition changes
SETLOCALDEFS=0
" > /etc/sysconfig/selinux 
    setenforce 0
    mkdir -p /root/.ssh
    cp -rp /vagrant/.ssh/* /root/.ssh
    cp -rp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/id_rsa
    chmod 644 /root/.ssh/id_rsa.pub
    chmod 600 /root/.ssh/authorized_keys
    chown -R root /root/.ssh
    chgrp -R root /root/.ssh
}


function setup_pgpool(){
	$PKG -y install $PGPOOL_PKG
	rm -f $PGPOOL_DIR/*
	cp /vagrant/pgpool/* $PGPOOL_DIR/
	cat /vagrant/pgpool/.pcppass > $PGPOOL_DIR/.pcppass
	cat /vagrant/pgpool/pgpool-"$(hostname)".conf > $PGPOOL_DIR/pgpool.conf
	chmod 600 $PGPOOL_DIR/.pcppass
	mkdir -p /var/run/pgpool/ /var/log/pgpool/
	chown -R postgres.postgres /var/run/pgpool/ $PGPOOL_DIR/ /var/log/pgpool/
	# disable pgpool2 from auto starting
	systemctl disable pgpool-II-10
    systemctl stop pgpool-II-10
    chmod 644 /usr/lib/systemd/system/pgpool-II-10.service 
}



function setup_pgbouncer() {
    $PKG -y install pgbouncer

    cat > /etc/pgbouncer/pgbouncer.ini <<EOF
[databases]
#postgres = host=172.28.33.10 pool_size=6
#template1 = host=172.28.33.10 pool_size=6

* = host=172.28.33.10 pool_size=6

[pgbouncer]
logfile = /var/log/postgresql/pgbouncer.log
pidfile = /var/run/postgresql/pgbouncer.pid
listen_addr = *
listen_port = 6432
unix_socket_dir = /var/run/postgresql
auth_type = trust
auth_file = /etc/pgbouncer/userlist.txt
admin_users = postgres
stats_users =
pool_mode = transaction
server_reset_query =
server_check_query = select 1
server_check_delay = 10
max_client_conn = 1000
default_pool_size = 12
reserve_pool_size = 5
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
ignore_startup_parameters = extra_float_digits
EOF

    cat > /etc/pgbouncer/userlist.txt <<EOF
"postgres" "whatever_we_trust"
EOF

    cat > /etc/default/pgbouncer <<EOF
START=1
EOF


echo "
# It's not recommended to modify this file in-place, because it will be
# overwritten during package upgrades.  If you want to customize, the
# best way is to create a file \"/etc/systemd/system/pgbouncer.service\",
# containing
#       .include /lib/systemd/system/pgbouncer.service
#       ...make your changes here...
# For more info about custom unit files, see
# http://fedoraproject.org/wiki/Systemd#How_do_I_customize_a_unit_file.2F_add_a_custom_unit_file.3F

[Unit]
Description=A lightweight connection pooler for PostgreSQL
After=syslog.target
After=network.target

[Service]
Type=forking

User=postgres
Group=postgres

# Path to the init file
Environment=BOUNCERCONF=/etc/pgbouncer/pgbouncer.ini
#
# #PIDFile=/var/run/pgbouncer/pgbouncer.pid
PIDFile=/var/run/postgresql/pgbouncer.pid

#
#
# Where to send early-startup messages from the server 
# This is normally controlled by the global default set by systemd
# StandardOutput=syslog

ExecStart=/usr/bin/pgbouncer -d -q \${BOUNCERCONF}
ExecReload=/usr/bin/kill -HUP \$MAINPID
KillSignal=SIGINT

# Give a reasonable amount of time for the server to start up/shut down
TimeoutSec=300

[Install]
WantedBy=multi-user.target
" > /usr/lib/systemd/system/pgbouncer.service

	systemctl daemon-reload
	systemctl enable pgbouncer.service
    chown pgbouncer.pgbouncer  /etc/default/pgbouncer 
    systemctl start pgbouncer.service  
}

function setup_fresh_postgresql() {


	
    mkdir -p $PG_CONF_EXT
    chown -R postgres.postgres $PG_CONF_EXT
    mkdir -p $PGDATA_BASE
    chown -R postgres.postgres $PGDATA_BASE
    su -s /bin/bash -c "$PG_BIN/bin/initdb -D $PGDATA/ -E utf-8" postgres


	    cat > $PGDATA/pg_hba.conf <<EOF
    local   all             postgres                                trust

    # TYPE  DATABASE        USER            ADDRESS                 METHOD

    # "local" is for Unix domain socket connections only
    local   all             all                                     trust
    # IPv4 local connections:
    host    all             all             127.0.0.1/32            md5
    # IPv6 local connections:
    host    all             all             ::1/128                 md5
    # Allow replication connections from localhost, by a user with the
    # replication privilege.
    #local   replication     postgres                                peer
    #host    replication     postgres        127.0.0.1/32            md5
    host    replication     postgres        ::1/128                 md5
    hostssl    replication     postgres 172.28.33.11/32              trust
    hostssl    replication     postgres 172.28.33.12/32              trust
    hostssl    replication     postgres 172.28.33.13/32              trust
    hostssl    replication     postgres 10.2.2.10/32                 trust
    hostssl    replication     postgres 10.2.2.11/32                 trust
    hostssl    replication     postgres 10.2.2.12/32                 trust
    hostssl    replication     postgres 10.2.2.13/32                 trust
    
    
    # for user connections
    host       all     postgres 172.28.33.1/32                 trust
    hostssl    all     postgres 172.28.33.1/32                 trust
    # for pgbouncer
    host       all     postgres 172.28.33.10/32                 trust
    hostssl    all     postgres 172.28.33.10/32                 trust
    host       all     postgres 172.28.33.11/32                 trust
    hostssl    all     postgres 172.28.33.11/32                 trust
    host       all     postgres 172.28.33.12/32                 trust
    hostssl    all     postgres 172.28.33.12/32                 trust
    host       all     postgres 172.28.33.13/32                 trust
    hostssl    all     postgres 172.28.33.13/32                 trust
	host       all     postgres 10.2.2.11/32                 trust
	hostssl    all     postgres 10.2.2.11/32                 trust
	host       all     postgres 10.2.2.12/32                 trust
	hostssl    all     postgres 10.2.2.12/32                 trust
	host       all     postgres 10.2.2.13/32                 trust
	hostssl    all     postgres 10.2.2.13/32                 trust
	host       all     postgres 10.2.2.10/32                 trust
	hostssl    all     postgres 10.2.2.10/32                 trust
EOF

    cat > $PGDATA/postgresql.conf <<EOF
archive_command = 'exit 0'
archive_mode = 'on'
autovacuum = 'on'
checkpoint_completion_target = 0.6
checkpoint_warning = 300
datestyle = 'iso, mdy'
default_text_search_config = 'pg_catalog.english'
effective_cache_size = '128MB'
external_pid_file = '/var/run/postgresql/${POSTGRESQL_VERSION}-main.pid'
hot_standby = 'on'
lc_messages = 'C'
listen_addresses = '*'
log_autovacuum_min_duration = 0
log_checkpoints = 'on'
logging_collector = 'on'
log_min_messages = DEBUG3
log_destination = 'stderr'              # Valid values are combinations of
logging_collector = on                  # Enable capturing of stderr and csvlog
log_directory = 'pg_log'
log_line_prefix = '%t [%p]: [%l-1] db=%d,user=%u '
log_filename = 'postgresql.log'
log_connections = 'on'
log_disconnections = 'on'
log_lock_waits = 'on'
log_min_duration_statement = 0
log_temp_files = 0
maintenance_work_mem = '128MB'
max_connections = 100
max_wal_senders = 5
port = 5432
shared_buffers = '128MB'
shared_preload_libraries = 'pg_stat_statements'
#unix_socket_directories = '/var/run/postgresql'
ssl = on
ssl_cert_file = '$PGDATA/ssl-cert-snakeoil.pem'
ssl_key_file = '$PGDATA/ssl-cert-snakeoil.key'
wal_buffers = '8MB'
wal_keep_segments = '200'
wal_level = 'hot_standby'
work_mem = '128MB'
EOF
    cp -pr /vagrant/ssl/ssl* $PGDATA/
    chmod 600 $PGDATA/ssl-cert-snakeoil.key
    chown postgres.postgres $PGDATA/ssl-cert-snakeoil.*
   

    sed -i  "s/Environment\=PGDATA\=\/var\/lib\/pgsql\/${POSTGRESQL_VERSION}\/data\//Environment\=PGDATA\=\/bd\/postgres\/${POSTGRESQL_VERSION}\/pgsql\/data/g" /usr/lib/systemd/system/postgresql-${POSTGRESQL_VERSION}.service
    sed  -i "s/PGDATA\=\/var\/lib\/pgsql\/${POSTGRESQL_VERSION}\/data/PGDATA\=\/bd\/postgres\/${POSTGRESQL_VERSION}\/pgsql\/data/g" /var/lib/pgsql/.bash_profile  
    # start postgresql to set things up before copying
    systemctl start postgresql-${POSTGRESQL_VERSION}.service
    su - postgres -c "$PG_BIN/bin/psql -c \"ALTER USER postgres  WITH PASSWORD 'postgres';\"" 2>> /tmp/x 1>> /tmp/x
    su - postgres -c "$PG_BIN/bin/createdb teste" 2>> /tmp/x 1>> /tmp/x
     su - postgres -c "$PG_BIN/bin/pgbench -i -s 10 teste" 2>> /tmp/x 1>> /tmp/x
    su - postgres -c "$PG_BIN/bin/psql -c \"create extension pgagent;\"" 2>> /tmp/x 1>> /tmp/x
    systemctl stop postgresql-${POSTGRESQL_VERSION}.service


    ssh -o StrictHostKeyChecking=no $PG02 "mkdir -p $PGDATA"
    ssh -o StrictHostKeyChecking=no $PG03 "mkdir -p $PGDATA"
    rsync -avz -e 'ssh -oStrictHostKeyChecking=no' $PGDATA/ $PG02:$PGDATA
    rsync -avz -e 'ssh -oStrictHostKeyChecking=no' $PGDATA/ $PG03:$PGDATA
    echo "export PATH=/usr/pgsql-10/bin:$PATH
alias ph='cd $PGDATA'
alias pgl='cd $PGDATA/pg_log'
" >> /var/lib/pgsql/.bash_profile 
    scp -o StrictHostKeyChecking=no -p /var/lib/pgsql/.bash_profile $PG02:/var/lib/pgsql/.bash_profile 
    scp -o StrictHostKeyChecking=no -p /var/lib/pgsql/.bash_profile $PG03:/var/lib/pgsql/.bash_profile 
  

}

function setup_postgresql_repo() {
    # Setup postgresql repo key
    $PKG -y install http://download.postgresql.org/pub/repos/yum/${POSTGRESQL_VERSION}/redhat/rhel-7-x86_64/pgdg-centos${POSTGRESQL_VERSION}-${POSTGRESQL_VERSION}-2.noarch.rpm
    # Update package info
    $PKG update
    # Upgrade all the (safe) packages to start from a clean slate
   # $PKG -y upgrade
}


function setup_postgresql() {
    # Install postgresql
    $PKG -y install postgresql10-server-10.3-1PGDG.rhel7.x86_64 postgresql10-contrib-10.3-1PGDG.rhel7.x86_64 postgresql10-libs-10.3-1PGDG.rhel7.x86_64
    $PKG -y install https://rpmfind.net/linux/epel/7/x86_64/Packages/w/wxBase-2.8.12-20.el7.x86_64.rpm pgagent_10.x86_64
    
     $PKG -y install centos-release-scl
     $PKG -y install rh-python36

    # disable postgresql from auto starting
    systemctl disable postgresql-${POSTGRESQL_VERSION}.service
    systemctl stop  postgresql-${POSTGRESQL_VERSION}.service

    cp -pr /vagrant/ssl /etc

    chown -R postgres.postgres  /etc/ssl

    cp /vagrant/resource_agents/pg_init_replic_pcmk.sh /var/lib/pgsql
    chown  postgres.postgres  /var/lib/pgsql/pg_init_replic_pcmk.sh
    chmod +x /var/lib/pgsql/pg_init_replic_pcmk.sh
    # we will recreate this later in preparation for pacemaker
    rm -rf $PGDATA
    mkdir -p /var/log/postgresql/
    chown -R postgres.postgres /var/log/postgresql/
    #chmod -R 777 /var/run/postgresql
    
  
}

function setup_cluster() {

    
   cat < /etc/yum.repos.d/centos.repo 
[centos-7-base] 
name=CentOS-$releasever - Base 
mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os 
#baseurl=http://mirror.centos.org/centos/$releasever/os/$basearch/ 
enabled=1 
EOF

cat >> /etc/hosts <<EOF
$PG01 $NODE1
$PG02 $NODE2
$PG03 $NODE3
EOF

    

    # Install cluster packages
    $PKG -y install corosync pacemaker pcs resource-agents net-tools vim mlocate ntp psmisc policycoreutils-python wget
	cd /etc/yum.repos.d/
	OSVERSION=$(cat /etc/centos-release | sed -rn 's/.* ([[:digit:]]).*/\1/p')
	wget http://download.opensuse.org/repositories/network:/ha-clustering:/Stable/CentOS_CentOS-${OSVERSION}/network:ha-clustering:Stable.repo
	$PKG -y install crmsh
    cd -
    systemctl start pcsd.service 
    systemctl enable pcsd.service

    echo chengeme | passwd --stdin hacluster 
#    pcs cluster auth $NODE1 $NODE2 $NODE3 -u hacluster -p CHANGEME --force

    # Setup corosync config
    mkdir -p /var/log/corosync/

    cp /vagrant/corosync/corosync.conf /etc/corosync/corosync.conf
    cp /vagrant/corosync/authkey /etc/corosync/authkey

    # Install our patched version of the pgsql resource
    cp /vagrant/resource_agents/pgsql /usr/lib/ocf/resource.d/heartbeat/pgsql

    #cp /vagrant/resource_agents/pgpool2 /usr/lib/ocf/resource.d/heartbeat/pgpool2
    
    cp /vagrant/resource_agents/pgpool.in /usr/lib/ocf/resource.d/heartbeat/pgpool
    
    chmod 755 /usr/lib/ocf/resource.d/heartbeat/pgpool
    
    
    cp /vagrant/resource_agents/pgagent.in /usr/lib/ocf/resource.d/heartbeat/pgagent
    
    chmod 755 /usr/lib/ocf/resource.d/heartbeat/pgagent
 
    # Make sure corosync can start
    cat > /etc/default/corosync <<EOF
START=yes
EOF

<<'END'
    # Make sure pacemaker is setup
    cat > /etc/corosync/service.d/pacemaker <<EOF
service {
    name: pacemaker
    ver: 1
}
EOF
END

    # start corosync / pacemaker
    systemctl start corosync
    
    # TODO: check output of corosync-cfgtool -s says "no faults"
    systemctl start pacemaker

    systemctl enable pacemaker
    systemctl enable corosync
}

# TODO: have a way to customise op monitor intervals during cluster turnup
# Currently they're set to the values we use during deliberate migrations
function build_cluster() {
    printf "Waiting for cluster to have quorum"
    while [ -z "$(pcs status | grep '3 nodes configured')" ]; do
        sleep 1
        printf "."
    done
    echo " done"

    # setup new postgresql instance that is exactly the same in all boxes
    setup_fresh_postgresql


    # deploy cluster
	rm -f pgsql_cfg 2>/dev/null


	pcs -f pgsql_cfg property set no-quorum-policy="ignore"
	pcs -f pgsql_cfg property set stonith-enabled="false"
	pcs -f pgsql_cfg resource defaults resource-stickiness="100"
	pcs -f pgsql_cfg resource defaults migration-threshold="1"

	pcs -f pgsql_cfg resource create PostgresqlVIP ocf:heartbeat:IPaddr2 \
	   ip="$VIP_PG" \
	   nic="$ETH_PG" \
	   cidr_netmask="24" \
	   op start   timeout="60s" interval="0s"  on-fail="restart" \
	   op monitor timeout="60s" interval="5s"  on-fail="restart" \
	   op stop    timeout="60s" interval="0s"  on-fail="block"

	pcs -f pgsql_cfg resource create ReplicationVIP ocf:heartbeat:IPaddr2 \
	   ip="$VIP_REPLICATION" \
	   nic="$ETH_REPLIC" \
	   cidr_netmask="24" \
	   op start   timeout="60s" interval="0s"  on-fail="restart" \
	   op monitor timeout="60s" interval="5s"  on-fail="restart" \
	   op stop    timeout="60s" interval="0s"  on-fail="block"


	pcs -f pgsql_cfg resource create PgBouncerVIP ocf:heartbeat:IPaddr2 \
	   ip="$VIP_PGBOURCER" \
	   nic="$ETH_PGBOUNCER" \
	   cidr_netmask="24" \
	   meta migration-threshold="0" \
	   op start   timeout="60s" interval="0s"  on-fail="stop" \
	   op monitor timeout="60s" interval="5s"  on-fail="restart" \
	   op stop    timeout="60s" interval="0s"  on-fail="ignore"

	pcs -f pgsql_cfg resource create Postgresql ocf:heartbeat:pgsql \
	   pgctl="/usr/pgsql-${POSTGRESQL_VERSION}/bin/pg_ctl" \
	   psql="/usr/pgsql-${POSTGRESQL_VERSION}/bin/psql" \
	   pgdata="$PGDATA" \
	   rep_mode="sync" \
	   node_list="${NODES[*]}" \
	   restore_command="exit 0" \
	   repuser="postgres" \
	   primary_conninfo_opt="keepalives_idle=60 keepalives_interval=5 keepalives_count=5" \
	   master_ip="$VIP_REPLICATION" \
	   restart_on_promote='true' \
	   op start   timeout="120s" interval="0s"  on-fail="restart" \
	   op monitor timeout="60s" interval="2s" on-fail="restart" \
	   op monitor timeout="60s" interval="1s"  on-fail="restart" role="Master" \
	   op promote timeout="120s" interval="0s"  on-fail="restart" \
	   op demote  timeout="120s" interval="0s"  on-fail="stop" \
	   op stop    timeout="120s" interval="0s"  on-fail="block" \
	   op notify  timeout="90s" interval="0s"

	pcs -f pgsql_cfg resource create Pgpool ocf:heartbeat:pgpool \
	 pgpoolconf="/etc/pgpool-II-10/pgpool.conf" \
					pcpconf="/etc/pgpool-II-10/pcp.conf" \
					options="-D"  pgpooluser="postgres" \
					checkmethod="pcp" \
					checkstring="-w -h 127.0.0.1 -p 9898 -U pgpool" \
					pgpoolcmd="/usr/pgpool-10/bin/pgpool" \
					pcpnccmd="/usr/pgpool-10/bin/pcp_node_count" \
					pcpnicmd="/usr/pgpool-10/bin/pcp_node_info" \
					pcpatcmd="/usr/pgpool-10/bin/pcp_attach_node" \
					pcpdtcmd="/usr/pgpool-10/bin/pcp_detach_node" \
					dsocketdir="/var/run/postgresql" \
					portpgpool="9999" \
					portpcp="9898" \
					pcppass="/etc/pgpool-II-10/.pcppass" \
	  op start   interval=0s  timeout=60s on-fail="restart" \
	  op monitor interval=30s timeout=30s on-fail="restart" \
	  op stop    interval=0s  timeout=60s
	  


	pcs -f pgsql_cfg resource create Pgagent ocf:heartbeat:pgagent \
	  connection_string="user=postgres host=/var/run/postgresql dbname=postgres" \
			   options="-r 1 -t 1"  \
			   user="postgres" \
	  op start   interval=0s  timeout=60s \
	  op monitor interval=30s timeout=30s \
	  op stop    interval=0s  timeout=60s


	pcs -f pgsql_cfg resource master msPostgresql Postgresql \
	   master-max=1 master-node-max=1 clone-max=3 clone-node-max=1 notify=true

	pcs -f pgsql_cfg resource group add master-group PostgresqlVIP ReplicationVIP

	pcs -f pgsql_cfg constraint colocation add PgBouncerVIP with Master msPostgresql 100 id="pgbouncer-vip-prefers-master"

	pcs -f pgsql_cfg constraint  colocation add Started master-group with Master msPostgresql id="vip-with-master"


	pcs -f pgsql_cfg constraint colocation add Pgpool with Master msPostgresql INFINITY id="pgpool-with-ip"
	pcs -f pgsql_cfg constraint colocation add Pgagent with Master msPostgresql INFINITY id="pgagent-with-ip"


	pcs -f pgsql_cfg constraint order promote msPostgresql then start master-group symmetrical=false score=INFINITY
	pcs -f pgsql_cfg constraint order demote  msPostgresql then stop  master-group symmetrical=false score=0
	pcs -f pgsql_cfg constraint order PostgresqlVIP then Pgpool id="pgpool-after-ip" kind="Mandatory"
	pcs -f pgsql_cfg constraint order PostgresqlVIP then Pgagent id="pgagent-after-ip" kind="Mandatory"

	pcs cluster cib-push  pgsql_cfg

}

if [ ! -f /root/.ssh/id_rsa ]; then
    setup_ssh_keys
fi

if [ ! -f /etc/apt/sources.list.d/pgdg.list ]; then
    setup_postgresql_repo
fi

if [ ! -f /etc/postgresql/${POSTGRESQL_VERSION}/main/postgresql.conf ]; then
    setup_postgresql
fi

if [ ! -f /etc/pgbouncer/pgbouncer.ini ]; then
    setup_pgbouncer
fi

if [ ! -f /etc/pgpool-II/pgpool.conf ]; then
    setup_pgpool
fi


if [ ! -f /etc/corosync/corosync.conf ]; then
    setup_cluster
fi



# we only build the cluster on one of the nodes
if [ "$(hostname)" == "pg01" ]; then
    # TODO: don't run this if we already have a cluster formed
    build_cluster
fi
