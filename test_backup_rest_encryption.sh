# this script demonstrates:
# - setup of MariaDB encryption from scratch
# - configuration of OS users for server and backup. 
# - Backup user has no permission to modify data directory (so we guarantee that backup doesn't damage data)
# - Server user has no permission to modify backup (so we guarantee that only backup user can modify backups)
# - Example of xtrabackup commands which should be used in such environment
#
# Tested in docker on blank Ubuntu 16 xenual image with commands below :
# docker run -it --name script -v //c/Users/User/docker:/test ubuntu:16.04
# test/test_backup_rest_encryption.sh
#
# !!!!
# xtrabackup binary capable of dealing with rest encryption should be located 
# in folder provided in -v parameter above (i.e. located in /test folder)

set -e
export DEBIAN_FRONTEND=noninteractive
apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xF1656F24C74CD1D8
echo 'deb [arch=amd64,i386,ppc64el] http://lon1.mirrors.digitalocean.com/mariadb/repo/10.1/ubuntu xenial main' >> /etc/apt/sources.list

apt-get update

apt -y install mariadb-server openssl sudo vim

umask 077

# datadir
mkdir /dt
# directory with encryption file
mkdir /sec
# backup folder
mkdir /bkup

adduser --disabled-password --gecos "" mdb
adduser --disabled-password --gecos "" mdbbackup
# let backup user be part of mdb group to be able copy files
adduser mdbbackup mdb
# let mdb user read from backup for restore
adduser mdb mdbbackup 


keyfile=/sec/keys

touch $keyfile.txt

echo "1;770A8A65DA156D24EE2A093277530142" > $keyfile.txt &&
  echo "18;F5502320F8429037B8DAEF761B189D12F5502320F8429037B8DAEF761B189D12" >> $keyfile.txt &&
  openssl enc -aes-256-cbc -md sha1 -k secret -in $keyfile.txt -out $keyfile.enc || { echo "Cannot generate key file" >&2 ;  exit 4; }

# make sure original key files is not accessible to anyone
chmod 000 $keyfile.txt

# encoded key file should be read-accessible to mdb group
chown mdb:mdb /sec
chmod 550 /sec
chown mdb:mdb $keyfile.enc
chmod 440 $keyfile.enc

# data directory is write-accessible to mdb user and read-accessible to mdb group
chown mdb:mdb /dt
chmod 750 /dt

# backup directory is accessible to backup user only
chown mdbbackup:mdbbackup /bkup
chmod 750 /bkup

# remove my.cnf generated with installation
mv /etc/mysql/my.cnf /etc/mysql/my.cnf.original

# create new my.cnf
cat >> /etc/mysql/my.cnf <<EOL
[xtrabackup]
user=root
socket=/dt/m.sock
[client]
socket=/dt/m.sock
[mysqld]
plugin_load=file_key_management.so
file_key_management_encryption_algorithm=aes_cbc
file_key_management_filename=/sec/keys.enc
file_key_management_filekey=secret
innodb-buffer-pool-size=128M
innodb-encrypt-log=ON
innodb-encryption-rotate-key-age=2
innodb-encryption-threads=4
innodb-tablespaces-encryption
innodb-encrypt-tables=FORCE
socket=/dt/m.sock
log_error=/dt/error.log
EOL

chmod 444 /etc/mysql/my.cnf

# = 770 in octal
export UMASK_DIR=504

mysql_install_db --datadir=/dt --user=mdb
chown -R mdb:mdb /dt
chmod -R g+rX /dt

mysqld --datadir=/dt --socket=/dt/m.sock --user=mdb &
# let mysqld start
sleep 5
#download sakila if needed:

if [ ! -f /test/sakila-schema.sql ]; then
  wget -V &>/dev/null || apt-get -y install wget
  wget -P /test http://downloads.mysql.com/docs/sakila-db.tar.gz 
  tar -xzf /test/sakila-db.tar.gz -C /test --strip-components=1
fi
	
mysql < /test/sakila-schema.sql
mysql < /test/sakila-data.sql

umask 007
sudo -g mdb -u mdbbackup /test/xtrabackup --backup --target-dir=/bkup

mysqladmin shutdown

sudo -g mdb -u mdbbackup /test/xtrabackup --prepare --target-dir=/bkup

# let mysqld shutdown
sleep 5

rm -r /dt/*
chmod -R g+rX /bkup

# note user used is mdb now - the owner of /dt
sudo -g mdbbackup -u mdb /test/xtrabackup --copy-back --datadir=/dt --target-dir=/bkup

chown -R mdb:mdb /dt

mysqld --datadir=/dt --socket=/dt/m.sock --user=mdb &
# let mysqld start
sleep 5

mysql -e "show tables from sakila"
