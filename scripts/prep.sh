#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

image_dir=/srv/cloud-images

# display usage
function usage() {
  echo "`basename $0`: Download cloud image for specified Linux distro"
  echo "Usage:

`basename $0` -f <flavor>"

  exit 255
}

function bad_taste() {
  echo "Error: no flavor named ${flavor} -- exiting."
  exit 255
}

function image_present() {
  if [ -f "${image}" ]; then
    echo "Image for flavor ${flavor} has already been downloaded."
    exit 0
  else
    echo "Missing image for ${flavor}, downloading..."
  fi
}

function download_image() {
  wget -nc ${dlurl}
  if [ $? -ne 0 ]; then
      echo "Error: ${flavor} could not be downloaded."
      exit 255
  fi
}

function validate_image() {
    pwd
    # get the sha256 hash via curl
    curl ${shaurl} | grep $(basename ${dlurl}) > sha256
    if [ "${flavor}" == "bullseye" ]; then
        sha512sum -c sha256
    else
        sha256sum -c sha256
    fi
    if [ $? -eq 0 ]; then
        mv $(basename ${dlurl}) "${image}"
    else
        echo "Error: ${flavor} could not be validated after download."
        exit 255
    fi
}

function prep_image() {
    sudo virt-sysprep -a ${flavor}.qcow2 --network --update --selinux-relabel --install qemu-guest-agent
    if [ $? -eq 0 ]; then
        echo "Flavor ${flavor} prepped and ready in image ${flavor}.qcow2."
    fi
}

# get command-line args
while getopts "f:" OPTION; do
  case $OPTION in
    f) flavor=${OPTARG};;
    *) usage;;
  esac
done

if [ ${#} -eq 0 ]; then
  usage
fi

# turn the flavor variable into a location for images
case ${flavor} in
  jammy) image="${image_dir}/jammy.qcow2"; dlurl="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"; shaurl="https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS"; variant="ubuntu20.04";;
  alma9) image="${image_dir}/almalinux9.qcow2"; dlurl="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"; shaurl="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/CHECKSUM" variant="centos8";;
  rocky9) image="${image_dir}/rocky9.qcow2"; dlurl="https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"; shaurl="https://dl.rockylinux.org/pub/rocky/9/images/x86_64/CHECKSUM"; variant="rocky9";;
  bullseye) image="${image_dir}/bullseye.qcow2"; dlurl="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"; shaurl="https://cloud.debian.org/images/cloud/bullseye/latest/SHA512SUMS"; variant="debian10";;
  *) bad_taste;;
esac

# make the directory if necessary
if [ ! -d "${image_dir}" ]; then
    sudo mkdir "${image_dir}" && sudo chown $(whoami):$(id -gn) "${image_dir}"
fi

# do the work
image_present
pushd "${image_dir}"
download_image
validate_image
prep_image
popd

exit 0
