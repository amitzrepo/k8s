
# Kubernetes Installation
### 3 node Infrastructure with aws ec2.

Befor you get started , make sure, you have `terraform`, `ansible` installed.

### Current Folder structure looks like

> No modification needed in any of this file
```sh
├── inventory.yml
├── playbook.yml
├── main.tf
└── README.md
```

### Infrastructure Creation with Terraform

> On this stage I assume you have aws key and secret configure on your machine or where ever you are trying to run the terrform command.

```sh
terraform init

terraform validate

terraform plan -out plan.out

terraform apply plan.out
```

> Note that, In the terraform script in `main.tf` we have ansibel provider and that will create a dynamic ansible inventory for us

> Terraform also will create a `ssh key` file for us to be use for `ansible` or `ssh` command.

### Configuration Management with ansible

> ansible need below collection to be installed , so that ansible will read the dynamic inventory file generated by terraform.(Basicall that collection will read the inventory from terraform state file)

```sh
ansible-galaxy collection install cloud.terraform
```

##### View the dynamic inventory content

```sh
ansible-inventory -i inventory.yml --list --vars
```

##### Prepare the ssh key, to be used for ansibel or with ssh

```sh
terraform output -raw ssh_key >> id_rsa.pem

chmod 400 id_rsa.pem
```

##### Ping all the host by using ansible

```sh
ansible -i inventory.yml all -m ping
```

##### ansibel command to install kubernetes
```sh
ansible-playbook -i inventory.yml playbook.yml --syntax-check
```


### Kubernetes User creation

> ssh to the cluster and try to execute below command on the cluster it self.

[follow this official documentation](https://kubernetes.io/docs/tasks/administer-cluster/certificates/#openssl) or follow below steps.

##### Create an admin user

> Run these command on control-plain host

```sh
# user=samit

# Generate certificate for the user
openssl req -new -newkey rsa:2048 -nodes -keyout samit.key -out samit.csr -subj "/CN=samit"

sudo openssl x509 -req -in samit.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out samit.crt -days 30

# RBAC for the user
kubectl create clusterrolebinding samit-admin-binding --clusterrole=cluster-admin --user=samit

# Create kubeconfig file for the user
kubectl config set-cluster ec2-k8s --certificate-authority=/etc/kubernetes/pki/ca.crt --embed-certs=true --server=https://<cluster_vm_public_ip>:6443 --kubeconfig=samit-kubeconfig

kubectl config set-credentials samit --client-certificate=samit.crt --client-key=samit.key --embed-certs=true --kubeconfig=samit-kubeconfig

kubectl config set-context ec2-k8s-samit-context --cluster=ec2-k8s --user=samit --kubeconfig=samit-kubeconfig

kubectl config use-context ec2-k8s-samit-context --kubeconfig=samit-kubeconfig

# Test
kubectl --kubeconfig=samit-kubeconfig get pods
kubectl --kubeconfig=samit-kubeconfig get nodes

# or
export KUBECONFIG=$(pwd)/samit-kubeconfig
kubectl get pods
kubectl getnodes
 
```

##### Create a normal user with minimum access

> Run these command on control-plain host

```sh
#user=amit
openssl req -new -newkey rsa:2048 -nodes -keyout amit.key -out amit.csr -subj "/CN=amit"

sudo openssl x509 -req -in amit.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out amit.crt -days 30

kubectl create rolebinding amit-binding --clusterrole=view --user=amit --namespace=default

# Create kubeconfig file for the user
kubectl config set-cluster ec2-k8s --certificate-authority=/etc/kubernetes/pki/ca.crt --embed-certs=true --server=https://51.20.142.74:6443 --kubeconfig=amit-kubeconfig

kubectl config set-credentials amit --client-certificate=amit.crt --client-key=amit.key --embed-certs=true --kubeconfig=amit-kubeconfig

kubectl config set-context ec2-k8s-amit-context --cluster=ec2-k8s --user=amit --kubeconfig=amit-kubeconfig

kubectl config use-context ec2-k8s-amit-context --kubeconfig=amit-kubeconfig

# Test
kubectl --kubeconfig=amit-kubeconfig get pods #This will work and can be seen pods running on default namespace
kubectl --kubeconfig=amit-kubeconfig get nodes # Forbidden

```

After done the above steps, If you hit the below command , The config file will show something similar describe in `Sample kubeconfig file` section.

```sh
kubectl config --kubeconfig=samit-kubeconfig view
#or
kubectl config --kubeconfig=amit-kubeconfig view
```

> Some data might be base64 encoded on the config file. If you want the real data to be seen, make sure you decode it.

**Sample kubeconfig file**

```sh
apiVersion: v1
kind: Config
preferences: {}
clusters:
- cluster:
    certificate-authority-data: </etc/kubernetes/pki/ca.crt base64 encoded data>
    server: https://<HOST_IP>:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: <username>
  name: admin-context
users:
- name: <username>
  user:
    client-certificate-data: <path/to/user/file.crt>
    client-key-data: <path/to/user/file.key>
current-context: admin-context
```

Now it's time to copy both the config file i.e. `amit-kubeconfig` and `samit-kubeconfig` to the localhost machine from control-plain machine and use it from localhost machine. Make sure you have installed `kubectl` command

You are done! You should be able to use both the config file and access kubernetes cluster we have just created. If you are getting error , you have missed any of the above steps.

You can now set `KUBECONFIG` env variable or keep this file in your `$HOME/.kube` folder to use kubectl without extra argument

```sh
export KUBECONFIG=$(pwd)/samit-kubeconfig
#or
mv samit-kubeconfig $HOME/.kube/config

kubectl get pods
kubectl getnodes
```
---

More Tips: 

You can also use below k8s menifest to create a purify role and bind it for a dedicated user.

```yml
# Developer role with watch access
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: default
  name: developer
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["watch"]

# Binding the developer role to a user
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-binding
  namespace: default
subjects:
- kind: User
  name: developer-user
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io

# Deployment role with full access
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: deployer
rules:
- apiGroups: [""]
  resources: ["*"]
  verbs: ["*"]

# Binding the deployer role to a user
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: deployer-binding
subjects:
- kind: User
  name: deployer-user
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: deployer
  apiGroup: rbac.authorization.k8s.io

```

[back](../../../README.md)

scp -i id_rsa.pem ubuntu@13.61.5.139:/home/ubuntu/.kube/config /home/ubuntu/.kube