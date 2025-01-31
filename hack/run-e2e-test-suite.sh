#!/bin/bash

current_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
set -e

# Enable verbosity
if [ "$VERBOSE" = true ]; then
    set -o xtrace
fi

if [ "$#" -ne 3 ]; then
    echo "$0 <test_suite_name> <use_kind_cluster> <Jaeger Operator installed using OLM>"
    exit 1
fi

test_suite_name=$1
use_kind_cluster=$2
jaeger_olm=$3

# Prepare the cluster
if [ "$use_kind_cluster" == true ]; then
	kubectl wait --timeout=5m --for=condition=available deployment ingress-nginx-controller -n ingress-nginx
	kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=5m

	# Install metrics-server for scalability tests
	kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
	kubectl patch deployment -n kube-system metrics-server --type "json" -p '[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": --kubelet-insecure-tls}]'
	kubectl wait --for=condition=available deployment/metrics-server -n kube-system  --timeout=5m
fi

if [ "$jaeger_olm" = true ]; then
    echo "Skipping Jaeger Operator installation because JAEGER_OLM=true"
else
	echo Installing Jaeger Operator...
	# JAEGER_OPERATOR_VERBOSITY enables verbosity in the Jaeger Operator
	# JAEGER_OPERATOR_KAFKA_MINIMAL enables minimal deployment of Kafka clusters
	make cert-manager deploy JAEGER_OPERATOR_VERBOSITY=DEBUG JAEGER_OPERATOR_KAFKA_MINIMAL=true
	kubectl wait --timeout=5m --for=condition=available deployment jaeger-operator -n observability
fi


root_dir=$current_dir/../
reports_dir=$root_dir/reports

rm -f $reports_dir/$test_suite_name.xml

# Ensure KUTTL is installed
$current_dir/install/install-kuttl.sh
export KUTTL=$root_dir/bin/kubectl-kuttl

mkdir -p $reports_dir

cd $root_dir
make render-e2e-tests-$test_suite_name


echo Running $test_suite_name E2E tests
cd tests/e2e/$test_suite_name/_build

# Don't stop if something fails because we want to process the
# report anyway
set +e

$KUTTL test $KUTTL_OPTIONS --report xml
exit_code=$?

set -e

# The output XML needs some work because it adds "artifacts" as a test case.
# Also, the suites doesn't have a name so, we need to add one.
go install github.com/iblancasa/junitcli/cmd/junitcli@v1.0.1
junitcli --suite-name $test_suite_name --report --output $reports_dir/$test_suite_name.xml ./artifacts/kuttl-test.xml

if [ "$KIND_KEEP_CLUSTER" != true ] && [ "$use_kind_cluster" == true ]; then
	cd $root_dir
	make stop-kind
fi

exit $exit_code
