#!/usr/bin/env bash

#
# Copyright 2017 Sergey Rudyshin. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# this script is a unit test for gtbuild.sh

GTBUILD=${1:-"$PWD/gtbuild.sh"}

set -xue

mkdir -p "${TMP_DIR:=/tmp/$(date '+%F_%H%M%S').$$}"

cd $TMP_DIR

git init

cat <<EOF > build.gts
#                     PATCH              FULL
#   FILTER        FILES    EXT      FILES    EXT
parameters.sql    ALL      ANY      ALL      ANY
check_ver.sql     ALL      ANY      NONE     ANY
comp_a            CHANGED  LST      ALL      ANY
patches           CHANGED  ANY      NONE     ANY
PAR_STATELESS_EXTS="vw trg pks"
EOF

mkdir comp_a  patches


echo ""                             > parameters.sql
echo ""                             > check_ver.sql
echo "-- @depends on: comp_a/c.vw"  > comp_a/a.tab
echo "-- @depends on: comp_a/a.tab" > comp_a/a.trg
echo ""                             > comp_a/a.pks
echo "-- @depends on: comp_a/a.tab" > comp_a/b.tab
echo ""                             > comp_a/c.vw
echo ""                             > patches/cr_001.sql

git add .
git commit -m "initial commit"
git tag -a -m "v1.0" "v1.0"

echo "new" >> comp_a/a.tab
echo "new" >> comp_a/a.trg
echo "new" >> patches/cr_002.sql

FN=$(bash -x $GTBUILD)

PTH=${FN%/*}
PID=${PTH#/*\.}

cat <<EOF > full.sql.be
@parameters.sql
@comp_a/a.pks
@comp_a/c.vw
@comp_a/a.tab
@comp_a/a.trg
@comp_a/b.tab
EOF

cat <<EOF > patch.sql.be
@parameters.sql
@check_ver.sql
@comp_a/a.trg
@patches/cr_002.sql
EOF

cat <<EOF > archive.lst.be
build.gts
check_ver.sql
comp_a/
comp_a/a.pks
comp_a/a.tab
comp_a/a.trg
comp_a/b.tab
comp_a/c.vw
full.sql
parameters.sql
patches/
patches/cr_001.sql
patches/cr_002.sql
patch.sql
version
EOF

diff "$PTH/$PID/full.sql" full.sql.be

diff "$PTH/$PID/patch.sql" patch.sql.be

tar ztf $FN | sort > archive.lst.is

diff archive.lst.be archive.lst.is

echo SUCCESS
