#!/usr/bin/env bash

odin build src -out:dist/imgoptz_dev.exe -target:windows_amd64 -subsystem:console -debug -strict-style -vet -vet-packages:main -vet-unused-procedures -vet-tabs -disallow-do -warnings-as-errors
