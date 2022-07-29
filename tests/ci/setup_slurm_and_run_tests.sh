#!/bin/bash

set -x
set -e

# First install all packages built by the previous step

dnf -y install $(find /home/ohpc/rpmbuild/RPMS/ -name "*rpm") || true

# First recompile slurm with support for multiple slurmd on a single node

sed -i -e " \
	s,bcond_with multiple_slurmd,bcond_with multiple_slurmd\n%global _with_multiple_slurmd 1,g; \
	s,Release:.*$,Release: 99999,g;" components/rms/slurm/SPECS/slurm.spec

dnf -y install gcc make

tests/ci/run_build.py ohpc components/rms/slurm/SPECS/slurm.spec

dnf -y install /home/ohpc/rpmbuild/RPMS/x86_64/slurm-slurmd-ohpc* /home/ohpc/rpmbuild/RPMS/x86_64/slurm-slurmctld-ohpc* /home/ohpc/rpmbuild/RPMS/x86_64/slurm-example-configs-ohpc* /home/ohpc/rpmbuild/RPMS/x86_64/slurm-ohpc*

# Setup slurm

echo "127.0.0.1 node0 node1" >> /etc/hosts

cp /etc/slurm/slurm.conf.example /etc/slurm/slurm.conf

sed -i -e "
	s,SlurmdLogFile=.*$,SlurmdLogFile=/var/log/slurmd.%n.log,g; \
	s,SlurmdSpoolDir=.*$,SlurmdSpoolDir=/var/spool/slurmd.%n,g; \
	s,SlurmdPidFile=.*$,SlurmdPidFile=/var/run/slurmd.%n.pid,g; \
	s,JobCompType=jobcomp/none,,g; \
	s,NodeName=.*$,,g; \
	s,PartitionName.*$,,g; \
	s,ReturnToService.*$,ReturnToService=2,g; \
	s,ControlMachine=.*$,ControlMachine=$HOSTNAME,g;" /etc/slurm/slurm.conf

{
	echo "NodeName=c0 NodeHostname=node0 Port=17004 CPUs=2"
	echo "NodeName=c1 NodeHostname=node1 Port=17005 CPUs=2"
	echo "PartitionName=normal Nodes=c0,c1 Default=YES MaxTime=24:00:00 State=UP"
} >> /etc/slurm/slurm.conf

chown root.root /var/log/munge

/usr/sbin/munged -f
/usr/sbin/slurmctld
slurmd -N c0
slurmd -N c1

sinfo
scontrol update nodename=c[0-1] state=idle

srun -N2 hostname

dnf -y install automake autoconf prun-ohpc which gnu9-compilers-ohpc cmake-ohpc fftw-gnu9-mpich-ohpc fftw-gnu9-openmpi4-ohpc gsl-gnu9-ohpc

# Running Open MPI tests as root requires following variables to be set

export OMPI_ALLOW_RUN_AS_ROOT=1
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

# Run the tests

cd tests || exit 1
./bootstrap
./configure --disable-all --enable-cmake --enable-compilers --enable-mpi --with-mpi-families="mpich openmpi4" --enable-fftw --enable-gsl
make check
