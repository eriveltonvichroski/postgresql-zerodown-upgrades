#/bin/bash

VIP_REPLICATION="10.2.2.10"
PGDATABASE=/bd/postgres/10/pgsql
PGDATA=$PGDATABASE/data



if [ $(ip addr | grep $VIP_REPLICATION | wc -l) -gt 0 ]; then
   
   echo "Este node $hostname esta atribuido como master na replicacao"
   echo "Caso aconteca o rm -rf $PGDATABASE havera perda de dados"
   echo Configuracao abortada...
   exit 1
fi



echo
echo "rm -rf $PGDATABASE ?"
Opcao=
read Opcao
while [ "x$Opcao" != "xs" -a "x$Opcao" != "xn" ]; do
      echo -e "Deseja Continuar? (s/n)\c"
      read Opcao
done
if [ "$Opcao" = "n" ]; then
   echo Configuracao abortada...
   exit 1
fi

pg_ctl stop -m i

mkdir -p /bd/postgres/10/.conf_crm

cp -pf $PGDATA/p*.conf  /bd/postgres/10/.conf_crm

rm -rf $PGDATABASE
pg_basebackup -h $VIP_REPLICATION -U postgres -D $PGDATA -X stream -P

cp -pf  /bd/postgres/10/.conf_crm/p*.conf $PGDATABASE
rm -f /var/lib/pgsql/tmp/PGSQL.lock
