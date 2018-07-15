#!/bin/bash

set -x

if [ "$#" -ne 2 ]; then
	echo "SKIP. Please provide a git branch and range as parameter."
	exit 0
fi

. misc/shell-functions

ALREADY_PREPPED=0

prep() {
	if [ "${ALREADY_PREPPED}" == "1" ]; then
		return
	fi

	yum -y install rpm-build wget @development sudo

	# Out ohpc user to build the RPMs (if necessary)
	/usr/sbin/adduser ohpc
	local OHPC_VERSION_BASE=`echo ${GIT_BRANCH} | cut -d_ -f2 | cut -d. -f1-2`
	local OHPC_VERSION_UPDATE=`echo ${GIT_BRANCH} | cut -d_ -f2 | cut -d. -f3`

	curl "http://build.openhpc.community/OpenHPC:/${OHPC_VERSION_BASE}:/Factory/CentOS_7/OpenHPC:${OHPC_VERSION_BASE}:Factory.repo" > /etc/yum.repos.d/ohpc-base.repo

	# Check if this branch has a third part of the version number.
	# If this is something like 1.3 the following will be skipped, but not for 1.3.x.
	if [ ! -z ${OHPC_VERSION_UPDATE} ]; then
		for i in `seq 1 ${OHPC_VERSION_UPDATE}`; do
			curl "http://build.openhpc.community/OpenHPC:/${OHPC_VERSION_BASE}:/Update${i}:/Factory/CentOS_7/OpenHPC:${OHPC_VERSION_BASE}:Update${i}:Factory.repo" >> /etc/yum.repos.d/ohpc-update.repo
		done
	fi
	ALREADY_PREPPED=1
}

GIT_BRANCH=${1}

# check if it is a factory branch
if [[ "${GIT_BRANCH}" != "obs/OpenHPC_"* ]]; then
	echo "SKIP: Not a 'obs/OpenHPC_' branch. Not rebuilding SRPM."
	exit 0
fi

FAILED=0
NO_SPEC_FOUND=1

# List all files in this PR
for file in `git diff --name-only ${2}`; do
	# Find spec files for which RPMs should be built
	if [[  "${file}" == *"spec" ]]; then
		prep
		echo "Trying to rebuild SRPM for ${file}."
		NO_SPEC_FOUND=0
		# looks like a spec file was changed, let's rebuild
		SPEC=`basename ${file}`
		DIR=`dirname ${file}`
		prepare_git_tree ${DIR}
		misc/get_source.sh ${SPEC}
		echo "Creating SRPM."
		SRPM=`rpmbuild -bs --nodeps --define "_sourcedir ${DIR}/../SOURCES" ${file}`
		echo "Created SRPM ${SRPM}."
		RESULT=$?
		if [ "${RESULT}" == "1" ]; then
			echo "FAILED: Building SRPM for ${file} failed."
			FAILED=1
			continue
		fi
		SRPM=` echo ${SRPM} | tail -1 | awk -F\  ' { print $2 } ' `
		echo "Installing dependencies for ${SRPM}".
		yum-builddep --nogpgcheck -y ${SRPM}
		if [ -e /etc/profile.d/lmod.sh ]; then
			. /etc/profile.d/lmod.sh
		fi
		echo "Building RPM from ${SRPM}".
		cp ${SRPM} /tmp/
		chmod 644 /tmp/`basename ${SRPM}`
		sudo -u ohpc rpm -i /tmp/`basename ${SRPM}`
		sudo -i -u ohpc rpmbuild -ba /home/ohpc/rpmbuild/SPECS/${SPEC}
		RESULT=$?
		if [ "${RESULT}" == "1" ]; then
			echo "FAILED: Building binary RPM for ${file} failed."
			FAILED=1
		fi
	fi
done

if [ "${FAILED}" == "1" ]; then
	echo "FAILED: Something failed. Please look at the logs."
fi

if [ "${NO_SPEC_FOUND}" == "1" ]; then
	echo "SKIP: No SPEC file found in this commit range."
fi

exit ${FAILED}
