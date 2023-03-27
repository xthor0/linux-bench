#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

image_dir=/srv/cloud-images
target_dir=/var/lib/libvirt/images

# default options
flavor="rocky9"
ram=2
vcpus=1
storage=10
network=1
ifname="virbr0"


# display usage
function usage() {
  echo "`basename $0`: Deploy a cloud-init templated libvirt VM."
  echo "Usage:

`basename $0` -h <hostname of VM> [ -f <flavor> -t <network> -i <ip address> ]

where flavor is one of: bionic, focal, jammy, centos7, alma8, rocky8, buster, bullseye (default: ${flavor})
where <ip address> is in x.x.x.x/xx notation (default: dhcp)
and <network> is a VLAN tag of: 1, 50-55 (default: ${network})"

  exit 255
}

function bad_taste() {
  echo "Error: no flavor named ${flavor} -- exiting."
  exit 255
}

function check_tools() {
  # check if tools required by this script are installed
  for x in virt-sysprep mcopy virt-install; do
    which ${x} >& /dev/null 
    if [ $? -ne 0 ]; then
      echo "ERROR: Missing ${x} -- please install."
      exit 255
    fi
  done
}

function check_args() {
  # make sure we have necessary variables
  if [ -z "${host_name}" ]; then
    usage
  fi

  if [ ${#} -eq 0 ]; then
    usage
  fi

  # RAM is tricky, don't let me be stupid and specify more RAM than I have. Capping out at 16.
  if [ "${ram}" -gt 16 ]; then
      echo "Um, no, you can't have more than 16GB RAM."
      usage
  else
      memory=$((${ram} * 1024))
  fi
}

function pre_flight() {
  # network needs to be validated - expected to be a valid bridge interface name
  test -L /sys/class/net/${ifname}
  if [ $? -ne 0 ]; then
    echo "${ifname} for network ${network} is not a valid network interface - exiting."
    exit 255
  fi

  # is this VM already defined on the hypervisor?
  test -f /etc/libvirt/qemu/${vmname}.xml
  if [ $? -eq 0 ]; then
    echo "VM ${host_name} already defined -- exiting."
    exit 255
  fi

  # does this disk image already exist? Overwriting a running domain's disk, that's bad news, so don't do it.
  test -f ${disk_image}
  if [ $? -eq 0 ]; then
    echo "${disk_image} exists already -- exiting."
    exit 255
  fi
}

# get command-line args
while getopts "h:f:s:p:r:i:mu" OPTION; do
  case $OPTION in
    h) host_name=${OPTARG};;
    f) flavor=${OPTARG};;
    s) storage=${OPTARG};;
    p) vcpus=${OPTARG};;
    r) ram=${OPTARG};;
    i) ipaddr=${OPTARG};;
    m) salted="1";;
    u) update="--update";;
    *) usage;;
  esac
done

# turn the flavor variable into a location for images
case ${flavor} in
  jammy) image="${image_dir}/jammy.qcow2"; dlurl="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"; shaurl="https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS"; variant="ubuntu20.04";;
  alma9) image="${image_dir}/alma9.qcow2"; dlurl="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"; shaurl="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/CHECKSUM" variant="centos8";;
  rocky9) image="${image_dir}/rocky9.qcow2"; dlurl="https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"; shaurl="https://dl.rockylinux.org/pub/rocky/9/images/x86_64/CHECKSUM"; variant="rocky9";;
  bullseye) image="${image_dir}/bullseye.qcow2"; dlurl="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"; shaurl="https://cloud.debian.org/images/cloud/bullseye/latest/SHA512SUMS"; variant="debian10";;
  *) bad_taste;;
esac

check_tools
check_args
pre_flight

# variablize (is that a word?) this so I don't have to type it again in this script
disk_image=${target_dir}/${host_name}.qcow2

# create a temp dir for user-data and meta-data files
tmpdir=$(mktemp -d)

# for virt-sysprep --copy-in to work correctly, the directory name MUST be nocloud
mkdir ${tmpdir}/nocloud
if [ $? -ne 0 ]; then
  echo "Error creating ${tmpdir}/nocloud -- exiting."
  exit 255
fi

# copy the disk image to the right location, and then resize it
echo "Copying ${image} to ${disk_image} and resizing to ${storage}G..."
sudo cp ${image} ${disk_image} && sudo qemu-img resize ${disk_image} ${storage}G
if [ $? -ne 0 ]; then
  echo "Something went wrong either with copying the image, or resizing it -- exiting."
  exit 255
fi

# create a meta-data file
cat << EOF > ${tmpdir}/nocloud/meta-data
instance-id: 1
local-hostname: ${host_name}
EOF

# create user-data file
cat << EOF > ${tmpdir}/nocloud/user-data
#cloud-config
users:
    - name: root
      plain_text_passwd: resetm3n0w
      lock_passwd: false
      ssh_authorized_keys:
        - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDJNEonif7PNwf6DFR1/nqU9phsdgGFzSMO8EWkD3caLDoAs8/TvnQ+iwvzcox8yAKpU6uIaungjEil3LdiScQSB6yJXB++/4pO827+8AkYmo3seKWkk7LTpHuW8zPc8dbsre1uBCuV7VoAeMJkml1O4wwYooJVt55Nfj2qwVqbg7EMyO9C0KN6X85GLOV1WI3Oa95gmwJvnhg3sbFFW0l4DddsU7rmqzftHyfNzgg/X7VbBa1GzAhhr+EmCh19r8msAgVj6odKutk9/Z8bvE9kUH1+4c0WkdpeVOkdcacluRFZ3lrb9+UTdZ/H1ebTEKbpp/wg7eGT+pO4JcFNrqSqyiVkcBjYi6u8rzCJ3KjSy9718wwWM+y3m/NW0gCuuKTQnCeNqe+b1SUvvPZqGvMykGxStHszkVSDjuGZlu9IsP59ALSWDOvTkybu+fIONw4EmItrdPmGqGHYuA0tTzwLh4QqPr8fvF8sZaVislzHaPWzwaafKc2QpxjoABpfXdU= xthor@spindel.xthorsworld.com
        - ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBJxAV/7QW6fm8xwV05rDjh9eYZlXW54kBcSgfOVKVOAhSzzuH0+CmkZVL6vCYMBnkjGz/f33mp15WZBx4fjxLrw= default@secretive.spindel.local
    - name: xthor
      shell: /bin/bash
      plain_text_passwd: p@ssw0rd
      lock_passwd: false
      sudo: ALL=(ALL) NOPASSWD:ALL
      ssh_authorized_keys:
        - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDJNEonif7PNwf6DFR1/nqU9phsdgGFzSMO8EWkD3caLDoAs8/TvnQ+iwvzcox8yAKpU6uIaungjEil3LdiScQSB6yJXB++/4pO827+8AkYmo3seKWkk7LTpHuW8zPc8dbsre1uBCuV7VoAeMJkml1O4wwYooJVt55Nfj2qwVqbg7EMyO9C0KN6X85GLOV1WI3Oa95gmwJvnhg3sbFFW0l4DddsU7rmqzftHyfNzgg/X7VbBa1GzAhhr+EmCh19r8msAgVj6odKutk9/Z8bvE9kUH1+4c0WkdpeVOkdcacluRFZ3lrb9+UTdZ/H1ebTEKbpp/wg7eGT+pO4JcFNrqSqyiVkcBjYi6u8rzCJ3KjSy9718wwWM+y3m/NW0gCuuKTQnCeNqe+b1SUvvPZqGvMykGxStHszkVSDjuGZlu9IsP59ALSWDOvTkybu+fIONw4EmItrdPmGqGHYuA0tTzwLh4QqPr8fvF8sZaVislzHaPWzwaafKc2QpxjoABpfXdU= xthor@spindel.xthorsworld.com
        - ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBJxAV/7QW6fm8xwV05rDjh9eYZlXW54kBcSgfOVKVOAhSzzuH0+CmkZVL6vCYMBnkjGz/f33mp15WZBx4fjxLrw= default@secretive.spindel.local
timezone: America/Denver
package_upgrade: true
runcmd:
    - touch /etc/cloud/cloud-init.disabled
EOF

# virt-sysprep and inject user-data and meta-data
sudo virt-sysprep -a ${disk_image} --hostname ${host_name} --network --update --run-command 'mkdir -p /var/lib/cloud/seed' --copy-in ${tmpdir}/nocloud:/var/lib/cloud/seed --selinux-relabel
if [ $? -ne 0 ]; then
  echo "virt-sysprep exited with a non-zero status -- exiting."
  exit 255
fi

# kick off virt-install
echo "Installing VM ${host_name}..."
sudo virt-install --virt-type kvm --name ${host_name} --ram ${memory} --vcpus ${vcpus} \
  --os-variant ${variant} --network=bridge=${ifname},model=virtio --graphics vnc \
  --disk path=${disk_image},cache=writeback \
  --noautoconsole --import

# cleanup
rm -rf ${tmpdir}

# grab the MAC from the XML generated
# I don't think we'll ever see more than one, not in this setup, but just in case...
if [ $(sudo virsh domiflist ${host_name} | grep virbr0 | wc -l) -ne 1 ]; then
  echo "Unexpected output from \`virsh domiflist\` -- exiting."
  exit 255
fi

macaddr=$(sudo virsh domiflist ${host_name} | grep virbr0 | awk '{print $5 }')

# wait for the DHCP lease to show up
echo "waiting for DHCP lease..."
while true; do
  sudo virsh net-dhcp-leases default --mac ${macaddr} | grep -q ${macaddr}
  if [ $? -eq 0 ]; then
    echo -n "VM ${host_name} has IP address "
    sudo virsh net-dhcp-leases default --mac ${macaddr} | grep ${macaddr} | awk '{ print $5 }'
    break
  else
    sleep 5
  fi
done

exit 0
