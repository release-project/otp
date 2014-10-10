#!/bin/bash

# http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -eu
set -o pipefail
IFS=$'\n\t'

# Notes:
# - There are a few little differences between kernel.app.src and kernel.app,
#   but hopefully they don't matter much.

function print_help 
{
    echo "Usage: sd-install.sh <OTP installation directory>"
    exit 0
}

if [ "$#" -eq 0 ]; then
    print_help
fi

if [ "$1" = "-h" -o "$1" = "--help" ]; then
    print_help
fi

cd "$1"
echo "Installing SD-Erlang to $(pwd)"

# Show what you do
set -x

cd lib/kernel-*/
rm -rf sd_src
mkdir sd_src
for f in global.erl global_search.erl kernel.erl net_kernel.erl s_group.erl kernel.app.src; do
    curl https://raw.githubusercontent.com/release-project/otp/dev/lib/kernel/src/$f > sd_src/$f
done

if [ ! -f ebin_bak ]; then
    cp -r ebin ebin_bak
fi

cd ebin
../../../bin/erlc -I ../include ../sd_src/*.erl
cp ../sd_src/kernel.app.src kernel.app
echo "SD-Erlang installed."
