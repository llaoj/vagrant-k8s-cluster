#!/usr/bin/env bash

echo '====set timezone===='
timedatectl set-timezone Asia/Shanghai

cat >> /etc/hosts <<EOF
192.168.33.101 node1
192.168.33.102 node2
192.168.33.103 node3
EOF

# ====before install docker====
cat > /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
# Setup required sysctl params, these persist across reboots.
cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system
# disable swap
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab

# ====install docker====
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
# 官方源
# curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
# add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
# 阿里云源
curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get -y install docker-ce docker-ce-cli containerd.io
docker version

echo '====add user vagrant to docker group===='
egrep "^docker" /etc/group >& /dev/null
if [ $? -ne 0 ]
then
  groupadd docker
fi
usermod -aG docker vagrant

# ====set daocloud's registry mirror====
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "registry-mirrors" : ["https://thd69qis.mirror.aliyuncs.com"]
}
EOF
systemctl daemon-reload
systemctl restart docker
systemctl enable docker

# install k8s by kubeadm
apt-get update && apt-get install -y apt-transport-https curl
curl -s https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet
systemctl start kubelet

echo "====pull images from aliyun===="
repo_name="registry.aliyuncs.com/google_containers"
kubeadm config images pull --image-repository=${repo_name}
docker image list |grep ${repo_name} |awk '{print "docker tag ",$1":"$2,$1":"$2}' |sed -e "s#${repo_name}#k8s.gcr.io#2" |sh -x
docker image list


if [[ $1 -eq 1 ]]
then
	echo "====configure master node===="
	kubeadm init --apiserver-advertise-address=$2 --control-plane-endpoint=$2 --pod-network-cidr='10.244.0.0/16'
  mkdir -p $HOME/.kube
  cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  kubectl apply -f /vagrant/kube-flannel.yml
fi

if [[ $1 -eq 2 ]]
then
	echo "configure node2"
fi

if [[ $1 -eq 3 ]]
then
	echo "configure node3"
fi
