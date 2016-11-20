#!/bin/bash
# use this hack to allow mysqld service start on ubuntu docker image
# can be used e.g. like this:
# docker run -v $(pwd):/test --rm --name mm ubuntu:16.04 bash -c "cd test; ./fix-policy-rc.d.sh ; ./ubuntu_install_mariadb_from_mirror.sh.sh"

if [ "`wc -l < /usr/sbin/policy-rc.d`" == "2" ] && [ "`tail -n 1 /usr/sbin/policy-rc.d`" == "exit 101" ] 
then
	echo "#!/bin/sh" > /usr/sbin/policy-rc.d
	echo "exit 0" >> /usr/sbin/policy-rc.d
fi
