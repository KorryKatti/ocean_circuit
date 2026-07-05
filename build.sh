#!/bin/bash
set -e

mkdir -p bin
odin build src -out:bin/app
./bin/app
