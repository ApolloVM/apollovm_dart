#!/bin/bash

APIKEY=$1
shift  # remove the first argument (API key) from "$@"

## dart pub global activate dart_bump

dart_bump . \
  --extra-file "lib/src/apollovm_base.dart=String\\s+VERSION\\s+=\\s+['\"](.*)['\"]" \
  --api-key $APIKEY \
  "$@"
