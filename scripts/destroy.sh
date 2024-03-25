#!/bin/bash

set -e  # exit immediately on error
set -u  # fail on undeclared variables

kapp delete -y -a tanzu-rabbitmq-cluster
kapp delete -y -a tanzu-rabbitmq-package-install
kapp delete -y -a tanzu-rabbitmq-package-repository
kapp delete -y -a tanzu-rabbitmq-serviceaccounts
kapp delete -y -a tanzu-rabbitmq-secrets
kapp delete -y -a tanzu-rabbitmq-namespace

exit 0