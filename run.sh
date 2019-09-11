#!/bin/bash

chmod +x scripts/build.sh && scripts/build.sh "$@"
chmod +x scripts/add_project.sh && scripts/add_project.sh "$@"
chmod +x scripts/start_project.sh && scripts/start_project.sh "$@"