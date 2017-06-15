#!/bin/bash

# Applies requisite code formatters to the source tree

set -ex
SCRIPTPATH=$( cd "$(dirname "$0")" ; pwd -P )
source $SCRIPTPATH/use_bazel_go.sh

ROOTDIR=$SCRIPTPATH/..
cd $ROOTDIR

GO_FILES=$(git ls-files | grep -e '.*\.go' || exit 0)

if [[ -n "${GO_FILES}" ]]; then 
  UX=$(uname)

  #remove blank lines so gofmt / goimports can do their job
  for fl in ${GO_FILES[@]}; do
    if [[ ${UX} == "Darwin" ]];then
      sed -i '' -e "/^import[[:space:]]*(/,/)/{ /^\s*$/d;}" $fl
    else
      sed -i -e "/^import[[:space:]]*(/,/)/{ /^\s*$/d;}" $fl
  fi
  done
  gofmt -s -w ${GO_FILES}
  goimports -w -local istio.io ${GO_FILES}
fi
buildifier -showlog -mode=fix $(git ls-files | grep -e 'BUILD' -e 'WORKSPACE' -e '.*\.bazel' -e '.*\.bzl')
