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

# This is a build tool for scripts

set -e

BASETAG="*"
BUILDFILE="./build.gts"

function usage () {
    cat <<EOF
Usage: $0 [options] [<buildfile>]

Command line options:
    -b|--basetag    Pattern for the baseline's tag. Default is "*"

Default value for <buildfile> is "./build.gts"

Buildfile contains:
    - filters to select files for the target script
    - options

Buildfile filter format:
    A filter consists of five columns separated by spaces:
    col#1  - FILTER       - a string being used to filter the files
    col#2  - PATCH FILES  - applied in the patch-mode and can have one of the following
                          - ALL     - all the files are included
                          - CHANGED - only the changed files are included
    col#3  - PATCH EXT    - applied in the patch-mode and can have one of the following
                          - ANY     - do not filter by extension 
                          - LST     - to filter out the files based on its extensions
                                      the list of permitted extensions is in PAR_STATELESS_EXTS
    col#4  - FULL FILES   - similar to "PATCH FILES", but applied in the full-mode
    col#5  - FULL FILES   - similar to "PATCH EXT", but applied in the full-mode

Buildfile options:
    PAR_STATELESS_EXTS          List of file extensions not having any state
    PAR_INSTALL_SCRIPT_EXT      Extension for the target script
    PAR_ROOT_PATH               Path from <buildfile> to the root of the module
    PAR_DEPENDS_REGEXP          Expression determining the string which describes dependencies
    PAR_PREF                    Prefix to be inserted before each file in the target script
    PAR_VERSION_FILE            Name of the file containing the current and the base versions (commits)

EOF
    exit 1
}

while [[ $# -gt 1 ]]
do
    case "$1" in
        -b|--basetag)        
        BASETAG="$2"; shift ;;
        *)
        echo \"$1\" is an invalid option
        echo
        usage "$1"
        ;;
    esac
    shift
done

[[ -n "$1" ]] && BUILDFILE="$1"

PAR_STATELESS_EXTS="vw pks pkb fnc prc trg sta grt"
PAR_INSTALL_SCRIPT_EXT=".sql"
PAR_ROOT_PATH="."
PAR_DEPENDS_REGEXP=".*@depends on: *"
PAR_PREF="@"
PAR_VERSION_FILE="version"

PARAMS=$(grep 'PAR_.*=' -- "$BUILDFILE" | cat) 
eval "$PARAMS"

for opt in PAR_STATELESS_EXTS PAR_INSTALL_SCRIPT_EXT PAR_ROOT_PATH PAR_DEPENDS_REGEXP PAR_VERSION_FILE
do
    [[ "$(eval "echo \"\$$opt\"")" ]] || (echo "Please specify $opt"; echo ; usage)
done

set -u

mkdir -p "${TMP_DIR:=/tmp/$(date '+%F_%H%M%S').$$/$$}"

cd "${ROOT_PATH:=${BUILDFILE%/*}/$PAR_ROOT_PATH}"

BASELINE_TAG=$(git describe --match "${BASETAG}" --abbrev=0)
echo "base $(git rev-list -n 1 "$BASELINE_TAG")" > ${TMP_DIR}/$PAR_VERSION_FILE

ARCHIVE=${TMP_DIR%/$$}/$(git describe --match "${BASETAG}" --dirty).tar

cat <<EOF > $TMP_DIR/resolve_depends.awk
    function get_parent(child,lvl)  { 
        if (child != "" && (lvl < 100)) {
            return get_parent(parnt [child], (lvl+1)) " " child;
        }
    } 
    BEGIN {
        $(grep -R "$PAR_DEPENDS_REGEXP" | sed -e "s|:${PAR_DEPENDS_REGEXP}| |" -e 's|"||' \
            | awk '{print "parnt [\"" $1 "\"] = \"" $2 "\";" }')
    }
    {print get_parent(\$1, 0)}
EOF

TMP_LST="$TMP_DIR/lst"

find * -type f | awk -f $TMP_DIR/resolve_depends.awk | (LC_ALL=C; sort) \
    | tee ${TMP_LST}.ALL.depends | awk '$1 != "skip" {print $NF}' > ${TMP_LST}.ALL

GIT_ROOT=$(git rev-parse --show-toplevel)
RELATIVE_PATH=${PWD#${GIT_ROOT}/}
echo "current $(git rev-parse HEAD)" >> ${TMP_DIR}/$PAR_VERSION_FILE

git ls-files --others --full-name > ${TMP_LST}.not_yet_tracked

git diff --name-status $BASELINE_TAG \
    | awk '$1 != "D" {print $2}' > ${TMP_LST}.locally_changed

sed -e "s#^$RELATIVE_PATH/##" ${TMP_LST}.not_yet_tracked ${TMP_LST}.locally_changed > ${TMP_LST}.CHANGED.lkp

grep --line-regexp -f ${TMP_LST}.CHANGED.lkp ${TMP_LST}.ALL | cat > ${TMP_LST}.CHANGED

cd "$OLDPWD"

for the_delta in full patch
do
    awk '!/^#/ && !/^ *$/ && !/PAR_.*=/' "$BUILDFILE" \
    | while read FILE_FILTER PATCH_FILES PATCH_EXT FULL_FILES FULL_EXT
    do
        if [[ "$the_delta" == "full" ]] 
        then
            THE_FILES=$FULL_FILES
            THE_EXT=$FULL_EXT
        else
            THE_FILES=$PATCH_FILES
            THE_EXT=$PATCH_EXT
        fi

        if [[ "$THE_FILES" == "NONE" ]] 
        then
            THE_FILE=/dev/null
        else
            THE_FILE=${TMP_LST}.$THE_FILES
        fi

        if [[ "$THE_EXT" == "LST" ]] 
        then
            EXT_FILTER="\.(${PAR_STATELESS_EXTS// /|})$"
        else
            EXT_FILTER="."
        fi
        
        egrep "^${FILE_FILTER}" $THE_FILE | egrep "$EXT_FILTER" \
            | sed "s/^/$PAR_PREF/"

    done > $TMP_DIR/${the_delta}${PAR_INSTALL_SCRIPT_EXT}
done

cd "$ROOT_PATH"

tar -cf $ARCHIVE *

cd "${TMP_DIR}"

tar -uf  "$ARCHIVE" "$PAR_VERSION_FILE" "patch${PAR_INSTALL_SCRIPT_EXT}" "full${PAR_INSTALL_SCRIPT_EXT}"

gzip "$ARCHIVE"

cd "$OLDPWD"

[[ ${-/x} == $- ]]  && rm $TMP_DIR/* && rmdir $TMP_DIR

echo "$ARCHIVE.gz"
