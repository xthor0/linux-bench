#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

function setup_redhat() {
  sudo dnf install git ansible 
}

function setup_debian() {
  sudo add-apt-repository ppa:ansible/ansible && sudo apt update && sudo apt install git ansible
}

test -x $(which dnf) && setup_redhat
test -x $(which apt) && setup_debian

echo 0