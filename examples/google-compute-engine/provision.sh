#!/bin/bash -x

gpasswd -a ilya docker

/etc/init.d/kubelet stop

curl --silent --location http://git.io/weave --output /usr/local/bin/weave
chmod +x /usr/local/bin/weave

/usr/local/bin/weave launch-router --init-peer-count 7

/usr/local/bin/weave launch-proxy --rewrite-inspect

/usr/local/bin/weave connect kube-1
/usr/local/bin/weave expose -h $(hostname).weave.local

curl --silent --location http://git.io/scope --output /usr/local/bin/scope
chmod +x /usr/local/bin/scope

/usr/local/bin/scope launch --probe.kubernetes true --probe.kubernetes.api http://kube-apiserver.weave.local:8080

eval $(/usr/local/bin/weave env)

save_last_run_log_and_cleanup() {
  if [[ $(docker inspect --format='{{.State.Status}}' $1) = 'running' ]]
  then
    docker logs $1 > /var/log/$1_last_run
    docker rm $1
  fi
}

case "$(hostname)" in 
  kube-1)
    save_last_run_log_and_cleanup etcd1
    docker run -d \
      -e ETCD_CLUSTER_SIZE=3 \
      --name=etcd1 \
      weaveworks/kubernetes-anywhere:etcd
    break
    ;;
  kube-2)
    save_last_run_log_and_cleanup etcd2
    docker run -d \
      -e ETCD_CLUSTER_SIZE=3 \
      --name=etcd2 \
      weaveworks/kubernetes-anywhere:etcd
    break
    ;;
  kube-3)
    save_last_run_log_and_cleanup etcd3
    docker run -d \
      -e ETCD_CLUSTER_SIZE=3 \
      --name=etcd3 \
      weaveworks/kubernetes-anywhere:etcd
    break
    ;;
  kube-4)
    save_last_run_log_and_cleanup kube-apiserver
    save_last_run_log_and_cleanup kube-controller-manager
    save_last_run_log_and_cleanup kube-scheduler
    docker run -d \
      -e ETCD_CLUSTER_SIZE=3 \
      --name=kube-apiserver \
      weaveworks/kubernetes-anywhere:apiserver
    docker run -d \
      --name=kube-controller-manager \
      weaveworks/kubernetes-anywhere:controller-manager
    docker run -d \
      --name=kube-scheduler \
      weaveworks/kubernetes-anywhere:scheduler
    break
    ;;
  *)
    save_last_run_log_and_cleanup kubelet
    save_last_run_log_and_cleanup kube-proxy
    docker run \
      --volume="/:/rootfs" \
      --volume="/var/run/weave/weave.sock:/weave.sock" \
      weaveworks/kubernetes-anywhere:tools \
      setup-kubelet-volumes
    docker run -d \
      --name=kubelet \
      --privileged=true --net=host --pid=host \
      --volumes-from=kubelet-volumes \
      weaveworks/kubernetes-anywhere:kubelet
    docker run -d \
      --name=kube-proxy \
      --privileged=true --net=host --pid=host \
      weaveworks/kubernetes-anywhere:proxy
    ;;
esac