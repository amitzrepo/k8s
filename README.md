
## k8s infra in ec2

> Make sure, You have terraform, ansible installed.

**File structure** 

```sh
├── main.tf
├── inventory.yml
├── playbook.yml
└── README.md
```

**Infrastructure creation with terraform**

```sh
terraform init

terraform validate

terraform plan

terraform apply -auto-approve

```

> Terraform will create a Dynamic inventory file. Make sure you have below ansible galaxy module install.

```sh
ansible-galaxy collection install cloud.terraform
```

**To view the dynamic inventory.**

```sh
ansible-inventory -i inventory.yml --list --vars
```

**Fetch the ssh key to be use for ansibel ssh plugins.**

```sh
terraform output -raw ssh_key >> id_rsa.pem

chmod 400 id_rsa.pem
```

**Test , If all vm can be ping.**

```sh
ansible -i inventory.yml all -m ping
```

**ansibel**
```sh
ansible-playbook -i inventory.yml playbook.yml --syntax-check
```

**user creation**

```sh
    openssl genrsa -out amit.key 2048
    openssl req -new -key amit.key -out amit.csr -subj "/CN=amit"
    sudo openssl x509 -req -in amit.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out amit.crt -days 30

   kubectl config set-credentials amit --client-certificate=amit.crt --client-key=amit.key
   kubectl config set-context amit --cluster=kubernetes --namespace=default --user=amit
   kubectl create rolebinding amit-binding --clusterrole=view --user=amit --namespace=default
```