#!/bin/bash
set -e

cd "$(dirname "$0")"

mkdir -p bin
odin build src -out:bin/app
./bin/app
