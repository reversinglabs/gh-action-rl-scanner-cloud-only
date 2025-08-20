#! /bin/bash

convert_int_may_fail()
{
    # make sure we have a inner command that can fail
    # due to syntax error for invalid number (anything with a . will fail)
    declare -i what
    what=0

    if what="$1"
    then
        echo $what
    else
        echo $what
    fi
}

convert_int()
{
    declare -i what
    what=0

    # make sure we have a inner command that can fail
    # due to syntax error for invalid number (anything with a . will fail)
    # the defaul 0 will be returned on fail

    what=$( convert_int_may_fail "$1" 2>/dev/null )
    echo "${what}"
}

convert_bool()
{
    # any non valid input results in False
    local what="$1"
    local lower=$(
        echo "${what}" |
        tr '[:upper:]' '[:lower:]'
    )

    # int/string: 0 is false , 1 is true , all else is ignored and so false
    # string to lower: 'true' => True, 'false' => False, all else ingnored so False

    case "${lower}" in

    true|1)
        val=True
        ;;

    false|0)
        val=False
        ;;
    *)
        val=False
        ;;

    esac

    echo "${val}"
}

do_verbose()
{
    cat <<!
RL_PORTAL_SERVER:         M ${RL_PORTAL_SERVER:-No server was provided}
RL_PORTAL_ORG:            M ${RL_PORTAL_ORG:-No organization was provided }
RL_PORTAL_GROUP:          M ${RL_PORTAL_GROUP:- No group was provided}

MY_ARTIFACT_TO_SCAN_PATH: M ${MY_ARTIFACT_TO_SCAN_PATH:-No path was provided to scan}

RL_PACKAGE_URL:           M ${RL_PACKAGE_URL:-No package URL given: no diff scan can be executed}
RL_DIFF_WITH:             O ${RL_DIFF_WITH:-No diff with was requested}

RL_SUBMIT_ONLY:           O ${RL_SUBMIT_ONLY:-No submit-only flag was provided}
RL_TIMEOUT:               O ${RL_TIMEOUT:-No timeout was provided}
REPORT_PATH:              O ${REPORT_PATH:-No report path specified}

RLSECURE_PROXY_SERVER:    O ${RLSECURE_PROXY_SERVER:-No proxy server was provided}
RLSECURE_PROXY_PORT:      O ${RLSECURE_PROXY_PORT:-No proxy port was provided}
RLSECURE_PROXY_USER:      O ${RLSECURE_PROXY_USER:-No proxy user was provided}
RLSECURE_PROXY_PASSWORD:  O ${RLSECURE_PROXY_PASSWORD:-No proxy password was provided}
!
}

validate_mandatory_params()
{
    if [ -z "${RL_PACKAGE_URL}" ]
    then
        echo "::error FATAL: no 'RL_PACKAGE_URL' provided"
        exit 101
    fi

    if [ -z "${MY_ARTIFACT_TO_SCAN_PATH}" ]
    then
        echo "::error FATAL: no 'artifact-to-scan' provided"
        exit 101
    fi

    if [ -z "${RL_PORTAL_SERVER}" ]
    then
        echo "::error FATAL: no 'RL_PORTAL_SERVER' provided"
        exit 101
    fi

    if [ -z "${RL_PORTAL_ORG}" ]
    then
        echo "::error FATAL: no 'RL_PORTAL_ORG' provided"
        exit 101
    fi

    if [ -z "${RL_PORTAL_GROUP}" ]
    then
        echo "::error FATAL: no 'RL_PORTAL_GROUP' provided"
        exit 101
    fi

    if [ -z "${RLPORTAL_ACCESS_TOKEN}" ]
    then
        echo "::error FATAL: no 'RLPORTAL_ACCESS_TOKEN' is set in your environment"
        exit 101
    fi
}

prep_report()
{
    if [ -z "${REPORT_PATH}" ]
    then
        return 0
    fi

    if [ -d "${REPORT_PATH}" ]
    then
        if rmdir "${REPORT_PATH}"
        then
            :
        else
            echo "::error FATAL: your current REPORT_PATH is not empty"
            exit 101
        fi
    fi

    mkdir -p "${REPORT_PATH}"

    if [ "${RL_VERBOSE}" != "false" ]
    then
        ls -l "${REPORT_PATH}"
    fi
}

prep_paths()
{
    A_PATH=$( realpath "${MY_ARTIFACT_TO_SCAN_PATH}" )
    A_DIR=$( dirname "${A_PATH}" )
    A_FILE=$( basename "${A_PATH}" )

    R_PATH=""
    if [ ! -z "${REPORT_PATH}" ]
    then
        prep_report
        R_PATH=$( realpath "${REPORT_PATH}" )
    fi
}

makeDiffWith()
{
    DIFF_WITH=""

    if [ -z "${RL_DIFF_WITH}" ]
    then
        return
    fi

    DIFF_WITH="--diff-with=${RL_DIFF_WITH}"
}

prep_proxy_data()
{
    PROXY_DATA=""

    if [ ! -z "${RLSECURE_PROXY_SERVER}" ]
    then
        PROXY_DATA="${PROXY_DATA} -e RLSECURE_PROXY_SERVER=${RLSECURE_PROXY_SERVER}"
    fi

    if [ ! -z "${RLSECURE_PROXY_PORT}" ]
    then
        PROXY_DATA="${PROXY_DATA} -e RLSECURE_PROXY_PORT=${RLSECURE_PROXY_PORT}"
    fi

    if [ ! -z "${RLSECURE_PROXY_USER}" ]
    then
        PROXY_DATA="${PROXY_DATA} -e RLSECURE_PROXY_USER=${RLSECURE_PROXY_USER}"
    fi

    if [ ! -z "${RLSECURE_PROXY_PASSWORD}" ]
    then
        PROXY_DATA="${PROXY_DATA} -e RLSECURE_PROXY_PASSWORD=${RLSECURE_PROXY_PASSWORD}"
    fi
}

optional_timeout_and_submit()
{
    OPTIONAL_TS=""

    if [ ! -z "${RL_TIMEOUT}" ]
    then
        # we will not handle ant min, max or default here,
        # those can change based on rl-scanner-cloud

        # only if integer
        local val=$(
            convert_int "${RL_TIMEOUT}"
        )

        if [ "${val}" != "0" ]
        then
            OPTIONAL_TS="${OPTIONAL_TS} --timeout ${val}"
        fi
    fi

    if [ ! -z "${RL_SUBMIT_ONLY}" ]
    then
        # convert strings true/false
        local val=$( convert_bool "${RL_SUBMIT_ONLY}")
        # if true then specify '--submit-only' otherwise specify ''
        if [ "${val}" == "True" ]
        then
            OPTIONAL_TS="${OPTIONAL_TS} --submit-only"
        fi
    fi

    if [ "${RL_VERBOSE}" != "false" ]
    then
        echo "OPTIONAL_TS='${OPTIONAL_TS}'"
    fi
}

scan_with_portal()
{
    local - # auto restore the next line on function end
    set +e # we do our own error handling in this func
    set -x

    REPORT_VOLUME=""
    WITH_REPORT=""

    if [ "$R_PATH" != "" ]
    then
        REPORT_VOLUME="-v ${R_PATH}/:/reports"
        WITH_REPORT="--report-path=/reports --report-format=all --pack-safe"
    fi

    docker run --rm -u $(id -u):$(id -g) \
        -e "RLPORTAL_ACCESS_TOKEN=${RLPORTAL_ACCESS_TOKEN}" \
        ${PROXY_DATA} \
        -v "${A_DIR}/:/packages:ro" ${REPORT_VOLUME} \
        reversinglabs/rl-scanner-cloud:latest \
            rl-scan \
                --rl-portal-server "${RL_PORTAL_SERVER}" \
                --rl-portal-org "${RL_PORTAL_ORG}" \
                --rl-portal-group "${RL_PORTAL_GROUP}" \
                --purl=${RL_PACKAGE_URL} \
                --file-path="/packages/${A_FILE}" \
                --replace \
                --force \
                ${OPTIONAL_TS} ${DIFF_WITH} ${WITH_REPORT} 1>1 2>2
    RR=$?

    # TODO: is there a 'Scan result' string ?
    STATUS=$( grep 'Scan result:' 1 )
}

showStdOutErr()
{
    echo "::notice ## Stdout of reversinglabs/rl-scanner-cloud"
    cat 1
    echo

    echo "::notice ## Stderr of reversinglabs/rl-scanner-cloud"
    cat 2
    echo
}

test_missing_status()
{
    [ -z "$STATUS" ] && {
        showStdOutErr

        msg="Fatal: cannot find the scan result in the output"
        echo "::error::$msg"
        echo "$msg"             >> $GITHUB_STEP_SUMMARY
        echo "description=$msg" >> $GITHUB_OUTPUT
        echo "status=error"     >> $GITHUB_OUTPUT

        exit 101
    }
}

set_status_PassFail()
{
    echo "description=$STATUS" >> $GITHUB_OUTPUT
    echo "$STATUS"             >> $GITHUB_STEP_SUMMARY

    echo "$STATUS" | grep -q FAIL
    if [ "$?" == "0" ]
    then
        echo "status=failure" >> $GITHUB_OUTPUT
        echo "::error::$STATUS"
    else
        echo "status=success" >> $GITHUB_OUTPUT
        echo "::notice::$STATUS"
    fi
}

main()
{
    if [ "${RL_VERBOSE}" != "false" ]
    then
        do_verbose
    fi

    validate_mandatory_params
    prep_paths
    prep_proxy_data

    makeDiffWith
    optional_timeout_and_submit

    scan_with_portal

    if [ "${RL_VERBOSE}" != "false" ]
    then
        showStdOutErr
    fi

    test_missing_status
    set_status_PassFail

    exit ${RR}
}

main $@
