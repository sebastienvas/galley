#!/bin/bash
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_PATH="${ROOT}/bin"

bazel ${BAZEL_STARTUP_ARGS} build ${BAZEL_RUN_ARGS} \
  //... $(bazel query 'tests(//...)')

source ${BIN_PATH}/use_bazel_go.sh

cd ${ROOT}

PARENT_BRANCH=''

while getopts :c: arg; do
  case ${arg} in
    c) PARENT_BRANCH="${OPTARG}";;
    *) error_exit "Unrecognized argument ${OPTARG}";;
  esac
done

prep_linters() {
    echo "Preparing linters"
    if ! which gometalinter > /dev/null; then
        go get -u github.com/alecthomas/gometalinter
    fi
    if ! which buildifier > /dev/null; then
        go get -u github.com/bazelbuild/buildifier/buildifier
    fi
    if ! which codecoroner > /dev/null; then
        go get -u github.com/3rf/codecoroner
        gometalinter --install --vendored-linters >/dev/null
    fi
    bin/bazel_to_go.py
}

go_metalinter() {
    local parent_branch="${PARENT_BRANCH}"
    if [[ ! -z ${TRAVIS_PULL_REQUEST} ]];then
        # if travis pull request only lint changed code.
        if [[ ${TRAVIS_PULL_REQUEST} != "false" ]]; then
            LAST_GOOD_GITSHA=${TRAVIS_COMMIT_RANGE}
        fi
    elif [[ ! -z ${GITHUB_PR_TARGET_BRANCH} ]]; then
        parent_branch='parent'
        git fetch origin "refs/heads/${GITHUB_PR_TARGET_BRANCH}:${parent_branch}"
    fi

    if [[ -z ${LAST_GOOD_GITSHA} ]] && [[ -n "${parent_branch}" ]]; then
        LAST_GOOD_GITSHA="$(git log ${parent_branch}.. --pretty="%H"|tail -1)"
        [[ ! -z ${LAST_GOOD_GITSHA} ]] && LAST_GOOD_GITSHA="${LAST_GOOD_GITSHA}^"
    fi

    # default: lint everything. This runs on the main build
    PKGS=($(bazel query 'kind("go_library", //...)' | cut -d ':' -f 1 | sort | uniq | sed -e 's,//,./,g')) \
      || PKGS=()

    # convert LAST_GOOD_GITSHA to list of packages.
    if [[ ! -z ${LAST_GOOD_GITSHA} ]];then
        echo "Using ${LAST_GOOD_GITSHA} to compare files to."
        PKGS=$(for fn in $(git diff --name-only ${LAST_GOOD_GITSHA}); do fd="${fn%/*}"; [ -d ${fd} ] && echo $fd; done | sort | uniq)
    else
        echo 'Running linters on all files.'
    fi

    if [[ -z ${PKGS[@]} ]]; then
        echo 'No packages set'
    else
        gometalinter\
          --concurrency=4\
          --enable-gc\
          --vendored-linters\
          --deadline=600s --disable-all\
          --enable=aligncheck\
          --enable=deadcode\
          --enable=errcheck\
          --enable=gas\
          --enable=goconst\
          --enable=gofmt\
          --enable=goimports\
          --enable=golint --min-confidence=0 --exclude=.pb.go --exclude=pkg/config/proto/combined.go --exclude="should have a package comment"\
          --enable=gosimple\
          --enable=ineffassign\
          --enable=interfacer\
          --enable=lll --line-length=160\
          --enable=misspell\
          --enable=staticcheck\
          --enable=structcheck\
          --enable=unconvert\
          --enable=unused\
          --enable=varcheck\
          --enable=vet\
          --enable=vetshadow\
          ${PKGS[@]}
    fi

    # TODO: These generate warnings which we should fix, and then should enable the linters
    # --enable=dupl\
    # --enable=gocyclo\
    #
    # This doesn't work with our source tree for some reason, it can't find vendored imports
    # --enable=gotype\
}



run_linters() {
    echo Running linters
    go_metalinter
    ${BIN_PATH}/check_license.sh
    buildifier -showlog -mode=check $(git ls-files | grep -e 'BUILD' -e 'WORKSPACE' -e '.*\.bazel' -e '.*\.bzl')

    # TODO: Enable this once more of mixer is connected and we don't
    # have dead code on purpose
    # codecoroner funcs ./...
    # codecoroner idents ./...
}

prep_linters

run_linters

echo Done running linters
