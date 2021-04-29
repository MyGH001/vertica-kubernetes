#!/bin/bash

# The make targets and  the invoked shell scripts are directly run from the root directory.
function usage {
    echo "$0 -l <log_dir>  -n <cluster_name> -t <tag_name> [-h]"
    echo "  l   Log directory.   default: PWD"
    echo "  n   Name of the kind cluster. default: vertica"
    echo "  t   Tag. default: default-1"
    exit
}

OPTIND=1
while getopts l:n:t:h opt; do
    case ${opt} in
        l)
            INT_TEST_OUTPUT_DIR=${OPTARG}
            ;;
        n)
            CLUSTER_NAME=${OPTARG}
            ;;
        t)
            TAG=${OPTARG}
            ;;
        h)
            usage
            ;;
        \?)
            echo "ERROR: unrecognized option"
            usage
            ;;
    esac
done
shift "$((OPTIND-1))"

#Sanity Checks

if [ -z ${CLUSTER_NAME} ]; then
    CLUSTER_NAME=vertica
    echo "Assigned default value 'vertica' to CLUSTER_NAME"
fi

if [ -z ${TAG} ]; then
    TAG=default-1
    echo "Assigned default value 'default-1' to TAG"
fi

if [ -z ${INT_TEST_OUTPUT_DIR} ]; then
    INT_TEST_OUTPUT_DIR=${PWD}
fi


PACKAGES_DIR=docker-vertica/packages #RPM file should be in this directory to create docker image.
RPM_FILE=vertica-x86_64.RHEL6.latest.rpm
export INT_TEST_OUTPUT_DIR

# cleanup the deployed k8s cluster
function cleanup {
    make clean-deploy clean-int-tests 2> /dev/null # Removes the installed vertica chart and integration tests
    scripts/kind.sh term $CLUSTER_NAME
}

# Copy rpm to the PACKAGES_DIR for the image to be built
function copy_rpm {
    #This expects the rpm in $INT_TEST_OUTPUT_DIR and copies the file to $PACKAGES_DIR
    cp "$INT_TEST_OUTPUT_DIR"/"$RPM_FILE" "$PACKAGES_DIR"/"$RPM_FILE"
}

# Setup the k8s cluster and switch context
function setup_cluster {
    echo "Setting up kind cluster with $TAG tag and $CLUSTER_NAME name"
    scripts/kind.sh  init "$CLUSTER_NAME"
    if [ $? -ne 0 ]; then
      echo "Unable to create the $CLUSTER_NAME cluster"
      exit 1
    fi
    kubectx kind-"$CLUSTER_NAME"
}

# Setup integration tests
function setup_integration_tests {
    echo "Setting up integration tests"
    scripts/setup-int-tests.sh
    if [ $? -ne 0 ]; then
      echo "Unable to create the $CLUSTER_NAME cluster"
      exit 1
    fi
}

# Build vertica and python tools images, push to kind environment and deploy to the cluster
function build_and_deploy {
    echo "Building vertica and python tools container images"
    make  docker-build
    echo "Pushing the images to kind cluster"
    scripts/push-to-kind.sh -t $TAG "$CLUSTER_NAME"
    if [ $? -ne 0 ]; then
      echo "Unable to push the docker images to $CLUSTER_NAME nodes"
      exit 1
    fi
    echo "Deploy vertica in kind cluster"
    make  deploy-kind
}

# Run integration tests and store the pod status in a file
function run_integration_tests {
  echo "Saving the test status log in $INT_TEST_OUTPUT_DIR/integration_run.log "
  make run-int-tests > "$INT_TEST_OUTPUT_DIR"/integration_run.log
  echo "Saving final ocutpus pod status in $INT_TEST_OUTPUT_DIR/pod_status.csv "
  kubectl get pods --selector=testing.kyma-project.io/created-by-octopus=true > "$INT_TEST_OUTPUT_DIR"/pod_status.csv
}

trap cleanup EXIT
copy_rpm
setup_cluster
setup_integration_tests
build_and_deploy
run_integration_tests
cleanup