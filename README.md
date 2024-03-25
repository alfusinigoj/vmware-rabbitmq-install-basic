This repo contains a demonstration of installation of [VMware RabbitMQ for Kubernetes](https://docs.vmware.com/en/VMware-RabbitMQ-for-Kubernetes/index.html) using the repo, but exactly follows what was depicted in the article [Install VMware RabbitMQ in Kubernetes using Cluster Operator](https://www.alfusjaganathan.com/blogs/install-vmware-rabbitmq-kubernetes/)

The entire code in the repo is in templated format, which uses [ytt](https://carvel.dev/ytt/) for dynamically generating yaml configuration from declared values files.

Before continuing further, please have a look into the article [Install VMware RabbitMQ in Kubernetes using Cluster Operator](https://www.alfusjaganathan.com/blogs/install-vmware-rabbitmq-kubernetes/), which gives a better understanding of what is available in the repo and how we are going to process it.

### Prerequisites

- VMware RabbitMQ License and Acceptance of EULA
- Account at [PivNet](https://network.pivotal.io/)
- Kubernetes environment. In this case, I am using [Tanzu Kubernetes Grid (TKG)](https://tanzu.vmware.com/kubernetes-grid)
- Required operator privileges on the kubernetes cluster for installation
- [Cluster Essentials for VMware Tanzu](https://network.tanzu.vmware.com/products/tanzu-cluster-essentials) installed in the Kubernetes cluster.
- [Carvel Tools](https://carvel.dev/#install) installed
- [Kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- [kapp](https://carvel.dev/kapp/docs/v0.60.x/install/) installed
- [direnv](https://direnv.net/) installed

> Note: Refer to `Prerequisites before you Install VMware RabbitMQ for Kubernetes` section in [official documentation](https://docs.vmware.com/en/VMware-RabbitMQ-for-Kubernetes/1/rmq/installation.html) for more detailed information.


### Getting started

Clone the repository down to the workstation.

Connect to the Kubernetes cluster.

Summarized below are some of the kubernetes resources to be created in order to complete the installation, which we will see in detail later.

1. CertManager
1. Namespaces
1. Secrets, [SecretImports](https://github.com/carvel-dev/secretgen-controller/blob/develop/docs/secret-export.md) and [SecretExports](https://github.com/carvel-dev/secretgen-controller/blob/develop/docs/secret-export.md)
1. ServiceAccounts, ClusterRoles and ClusterRoleBindings
1. [PackageRepository](https://carvel.dev/kapp-controller/docs/v0.32.0/packaging/#package-repository)
1. [PackageInstall](https://carvel.dev/kapp-controller/docs/v0.32.0/packaging/#package-install)
1. [RabbitMQCluster](https://www.rabbitmq.com/kubernetes/operator/using-operator)

Let's get into each of the above, one by one, more detailed.

**CertManager:** This is `optional` if cert manager is already installed, if not run the below command. Update the version as needed.

  ```sh
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.5.3/cert-manager.yaml
  ```

**Setup Environment Variables and Secrets:** From the repo root folder, run the below command to create the environment secrets file.

  ```sh
  mv ./.envrc.secrets.template ./.envrc.secrets
  ```

  Update below **variables** in `./.envrc` and `./.envrc.secrets`

  ```
  export CFG_registry__username=
  export CFG_registry__password=
  ```

  Run command `direnv allow` so as to refresh the ENV onto your command scope. 

**Update YTT values:** Update the **value files** available in `values` folder as needed (especially the rabbitmq specific configuration, persistence_storage_class and persistence_storage)

Execute the below `kapp` commands in the given order, so as to create the rabbitmq cluster, its advisable to provide a few seconds of cooling time between execution of each command, especially after `package install` and `cluster`. It is also advisable to use `kubectl get` or `kubectl describe` command to verify these statuses.

**Namespaces:**: This creates the app `tanzu-rabbitmq-namespaces`, which creates the necessary **Namespaces**, one for `secrets`, second one for the `package install & package repository` and the third one for the `rabbitmq server cluster` itself. 

  ```sh
  ytt --ignore-unknown-comments -f ./templates/00-namespaces.yaml -f ./values/common.yaml --data-values-env CFG | kapp deploy -a tanzu-rabbitmq-namespaces -f- -y
  ```

**Secrets, SecretImports and SecretExports:** This creates the app `tanzu-rabbitmq-secrets`, which creates a kubernetes `secret` in `generic-secrets` namespace, then a [secret export](https://github.com/carvel-dev/secretgen-controller/blob/develop/docs/secret-export.md) and [SecretExports](https://github.com/carvel-dev/secretgen-controller/blob/develop/docs/secret-export.md) in `generic-secrets` namespace, which is used to export the `secret` to any targeted namespaces, which is configured by using a [secret import](https://github.com/carvel-dev/secretgen-controller/blob/develop/docs/secret-export.md) created at the target namespace. Here, the secret `tanzu-registry-credentials-secret` is exported to the namespaces `rabbitmq-installers` and `rabbitmq-clusters`.

  ```sh
  ytt --ignore-unknown-comments -f ./templates/01-secrets.yaml -f ./values/common.yaml --data-values-env CFG | kapp deploy -a tanzu-rabbitmq-secrets -f- -y
  ```

**ServiceAccounts, ClusterRoles and ClusterRoleBindings:** This creates the app `tanzu-rabbitmq-serviceaccounts`, which creates the necessary `cluster role`, `service account` and a `cluster role binding` providing required permissions to the `service account`. This is the service account which will be used by the package installer and the rabbitmq operators.

  ```sh
  ytt --ignore-unknown-comments -f ./templates/02-serviceaccount.yaml -f ./values/common.yaml --data-values-env CFG | kapp deploy -a tanzu-rabbitmq-serviceaccounts -f- -y
  ```

**PackageRepository:** This creates the app `tanzu-rabbitmq-package-repository`, which creates the necessary `package repository`, which pulls in the required packages from pivnet.

  ```sh
  ytt --ignore-unknown-comments -f ./templates/03-package-repository.yaml -f ./values/common.yaml --data-values-env CFG | kapp deploy -a tanzu-rabbitmq-package-repository -f- -y && sleep 30
  ```

  > Note 1: At this point you may have to accept EULA for the package `p-rabbitmq-for-kubernetes/tanzu-rabbitmq-package-repo` if not already.

  > Note 2: Better to wait for few seconds before running the next command or verify if the package is loaded using `kubectl get packages -A | grep " rabbitmq.tanzu.vmware.com.1.5.3"`

**PackageInstall:** Execute the below code block in a command shell to create the app `tanzu-rabbitmq-package-install`, which all the rabbitmq operators, here it is [Cluster Operator](https://docs.vmware.com/en/VMware-RabbitMQ-for-Kubernetes/1/rmq/kubernetes-operator-using-operator.html), [Messaging Topology Operator](https://docs.vmware.com/en/VMware-RabbitMQ-for-Kubernetes/1/rmq/kubernetes-operator-using-topology-operator.html) and [Standby Replication Operator](https://docs.vmware.com/en/VMware-RabbitMQ-for-Kubernetes/1/rmq/vmware_standby_repl_operator.html)

  ```sh
  ytt --ignore-unknown-comments -f ./templates/04-package-install.yaml -f ./values/common.yaml --data-values-env CFG | kapp deploy -a tanzu-rabbitmq-package-install -f- -y && sleep 30
  ```

**RabbitMQCluster:** Execute the below code block in a command shell to create the app `tanzu-rabbitmq-cluster`, which creates the RabbitMQ Server Cluster.

  ```sh
  ytt --ignore-unknown-comments -f ./templates/05-rabbitmqcluster.yaml -f ./values/rabbitmq.yaml -f ./values/common.yaml --data-values-env CFG | kapp deploy -a tanzu-rabbitmq-cluster -f- -y && sleep 45
  ```


We should have a cluster ready in few seconds, once available, we can obtain the IP address and the credentials as below.

**Obtain the IP address:** Execute the below command to retrieve the external IP address, or use any convenient method as your wish.

  ```sh
  kubectl get svc rabbitmq -n rabbitmq-clusters -o jsonpath="{.items[0].status.loadBalancer.ingress[0].ip}"
  ```

**Obtain the default username and password:** Execute the below commands to retrieve the username and password. 

  ```sh
  kubectl -n rabbitmq-clusters get secret rabbitmq-default-user -o jsonpath="{.data.username}" | base64 --decode
  kubectl -n rabbitmq-clusters get secret rabbitmq-default-user -o jsonpath="{.data.password}" | base64 --decode
  ```

Once you have the above information, you can open the management UI by launching `http://<IP Address>:15672` and log in using the obtained credentials.

Applications can connect to RabbitMQ server using port `5672`.

To quickly do a connectivity test using [RabbitMQ PerfTest](https://perftest.rabbitmq.com/), execute the below command after replacing IP address, username and password.

  ```sh
  docker run -it --rm pivotalrabbitmq/perf-test:latest --uri amqp://<username>:<password>@<IP Address>:5672 --id "connectivity test 1"
  ```

To manage the [Cluster Operator](https://docs.vmware.com/en/VMware-RabbitMQ-for-Kubernetes/1/rmq/kubernetes-operator-using-operator.html) from cli using [Kubectl](https://kubernetes.io/docs/tasks/tools/) plugin, follow the instruction [here](https://docs.vmware.com/en/VMware-RabbitMQ-for-Kubernetes/1/rmq/kubernetes-operator-kubectl-plugin.html?hWord=N4IghgNiBcIA4FMBOAzEBfIA).

### Uninstall

To uninstall the cluster, execute the below in a command shell where it is connected to the kubernetes cluster.

  ```sh
  ./scripts/destroy.sh
  ```

### References

- [Installation of Tanzu Rabbitmq](https://docs.vmware.com/en/VMware-RabbitMQ-for-Kubernetes/1/rmq/installation.html).
- [RabbitMQ Package Releases - Tanzu Network](https://network.pivotal.io/products/p-rabbitmq-for-kubernetes#/releases/1456120/artifact_references)
- [Tanzu CLI](https://docs.vmware.com/en/VMware-Tanzu-Application-Platform/1.7/tap/install-tanzu-cli.html)
- [Rabbitmq k8s Api Reference](https://github.com/rabbitmq/messaging-topology-operator/blob/main/docs/api/rabbitmq.com.ref.asciidoc)
- [Tanzu Rabbitmq Samples](https://github.com/vsphere-tmm/tkg-tanzu-rabbitmq/tree/main)

