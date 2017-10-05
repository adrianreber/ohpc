#!/bin/bash

# Install dependencies
yum -y install @development make

# Run Tests
./bootstrap; ./configure --disable-all --enable-cmake; make check
