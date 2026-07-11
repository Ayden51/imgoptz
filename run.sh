#!/usr/bin/env bash

odin run src -out:dist/imgoptz.exe -target:windows_amd64 -subsystem:console -o:speed -debug -strict-style -vet -vet-packages:main -vet-unused-procedures -vet-tabs -disallow-do -warnings-as-errors