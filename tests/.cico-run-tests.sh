#!/bin/bash

set -x

. ../misc/shell-functions

yum -y install git rpm-build wget @development

# Out ohpc user to build the RPMs (if necessary)
/usr/sbin/adduser ohpc

# copy the CBS repository definition
cp cico/cbs.repo /etc/yum.repos.d/cbs.repo

# We need to run configure as non root for correct test detection
chown ohpc.ohpc -R /root/payload
chmod 755 /root

FAILED=0

# List all files in this PR
for file in `git diff-tree --no-commit-id --name-only -r origin/${1}..origin/${2}`; do
	# Find spec files for which RPMs should be built
	if [[  "${file}" == *"spec" ]]; then
		# looks like a spec file was changed, let's rebuild
		pushd ..
		SPEC=`basename ${file}`
		DIR=`dirname ${file}`
		prepare_git_tree ${DIR}
		misc/get_source.sh ${SPEC}
		SRPM=`rpmbuild -bs --nodeps --define "_sourcedir ${DIR}/../SOURCES" ${file}`
		RESULT=$?
		if [ "${RESULT}" == "1" ]; then
			echo "Building SRPM for ${file} failed."
			FAILED=1
			continue
		fi
		SRPM=` echo ${SRPM} | tail -1 | awk -F\  ' { print $2 } ' `
		yum-builddep --nogpgcheck -y ${SRPM}
		sudo -u ohpc rpm -i ${SRPM}
		sudo -u ohpc -i rpmbuild -ba /home/ohpc/rpmbuild/SPECS/${SPEC}
		RESULT=$?
		if [ "${RESULT}" == "1" ]; then
			echo "Building binary RPM for ${file} failed."
			FAILED=1
		fi
		popd
	fi
done

if [ "${FAILED}" == "1" ]; then
	echo "Something failed. Please look at the logs."
fi

exit ${FAILED}

# Install dependencies
yum --nogpgcheck -y install libtool-ohpc autoconf-ohpc lmod-ohpc gnu7-compilers-ohpc

. /etc/profile.d/lmod.sh

module load autotools

./bootstrap

sudo -u ohpc ./configure --disable-all --enable-cmake --disable-silent-rules
make check
