M7VER=10.0.27
M7MAJOR=10.0
# todo !! test special characters in passwords
M7ROOTPWD=1

# detect os_distname
# PLATFORM

# DISTNAME=`python -c 'import platform; print platform.linux_distribution()[0].lower()'`
# DISTVER=`python -c 'import platform; print platform.linux_distribution()[1]'`
# DISTCODE=`python -c 'import platform; print platform.linux_distribution()[2].lower()'`

DISTNAME=`cat /etc/*release | grep -oP "^ID=\K.*"`
DISTVER=`cat /etc/*release | grep -oP "^VERSION_ID=\K.*"`
DISTCODE=`cat /etc/*release | grep -oP "^DISTRIB_CODENAME=\K.*"`

# ARCH=`python -c 'import platform; print platform.machine()'`
ARCH=`uname -m`

case $ARCH in 
x86_64) ARCH=amd64 ;;
*) echo "Unsupported platform ("$ARCH") - exiting" 1>&2 ; exit 1;;
esac


PUBKEY=0xcbcb082a1bb943db

[[ $DISTVER == 16* ]] && PUBKEY=0xF1656F24C74CD1D8

# example url ftp.hosteurope.de/mirror/archive.mariadb.org/mariadb-10.0.21/repo/ubuntu/pool/main/m/mariadb-10.0/mariadb-client-10.0_10.0.21%2bmaria-1~precise_amd64.deb

FOLDER=http://ftp.hosteurope.de/mirror/archive.mariadb.org/mariadb-$M7VER/repo/$DISTNAME/pool/main/m/mariadb-$M7MAJOR/

PKGLIST="libmysqlclient18 libmariadbclient18 mysql-common mariadb-common \
  mariadb-client-core-$M7MAJOR mariadb-client-$M7MAJOR mariadb-server-core-$M7MAJOR \
  mariadb-server-$M7MAJOR"

PKGARRAY=($PKGLIST)

# make sure nothing installed
dpkg -l | grep -iE "(mysql-server|mariadb-server)" && echo "It looks that server packages are already installed - exiting" && exit 1

# remove existing packages
# for (( idx=${#PKGARRAY[@]}-1 ; idx>=0 ; idx-- )) ; do
#	echo "${MYARRAY[idx]}"
#	apt-get remove ${PKGARRAY[idx]}
# done

# todo!!! check that repo is not there
set -e
apt-get -y install python-software-properties || (apt-get update && apt-get -y install python-software-properties)

apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 $PUBKEY\
 && add-apt-repository 'deb [arch=amd64,i386] http://mirror.one.com/mariadb/repo/'$M7MAJOR'/'$DISTNAME' '$DISTCODE' main' \
 && apt-get update

echo $?

wget -V > /dev/nul || apt-get install wget

download () {
        PACKAGE=$1

        if [[ $PACKAGE == *common* ]]; then
                FILE=$PACKAGE\_$M7VER+maria-1~$DISTCODE\_all.deb;
        else
                FILE=$PACKAGE\_$M7VER+maria-1~$DISTCODE\_$ARCH.deb;
        fi

        [[ -f $FILE ]] || (wget -nc $FOLDER$FILE || { err=$? ; echo "Error ("$err") downloading file: "$FOLDER$FILE 1>&2 ; exit $err; })
}

for i in ${PKGARRAY[@]}
do
        download $i
done

dpkg -i *common*$M7VER*$DISTCODE*.deb
dpkg -i lib*client*$M7VER*$DISTCODE*.deb

# this will install only dependancies, excluding upgrades and mysql/mariadb packages
# need derty hack with perl regexp below to actually include perl dependencies which have mysql in it
apt-install-depends() {
        apt-get install -s $@ \
      | sed -n \
        -e "/^Inst $pkg /d" \
        -e 's/^Inst \([^ ]\+\) .*$/\1/p' \
      | grep -v -P '(?=^(?:(?!perl).)*$).*mysql.*' \
      | grep -v mariadb \
      | grep -v updates \
      | xargs apt-get -y install
}

apt-install-depends ${PKGLIST[@]}

export DEBIAN_FRONTEND=noninteractive
debconf-set-selections <<< 'mariadb-server-$M7MAJOR mysql-server/root_password password '"$M7ROOTPWD"
debconf-set-selections <<< 'mariadb-server-$M7MAJOR mysql-server/root_password_again password '"$M7ROOTPWD"

dpkg -i *$M7VER*$DISTCODE*.deb

# let mysql server to start
# test connection
mysql -uroot -p"$M7ROOTPWD"  -e'select version()'
err=$?

echo "os="$DISTNAME:$DISTVER:$DISTCODE:$ARCH
echo "MariaDBServer=$M7VER"
if [ $err -eq 0 ] then;
	echo SUCCESS
else
	echo FAILURE
fi

exit $err
