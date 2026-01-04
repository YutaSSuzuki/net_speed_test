#!/usr/bin/env bash

for i in /sys/class/net/*; do
  iface=$(basename "$i")
  if [ -d "$i/wireless" ]; then
    echo "$iface : wireless"
  else
    echo "$iface : wired"
  fi
done
