#!/bin/sh
exec curl -fsSk --max-time 2 https://127.0.0.1:6443/healthz >/dev/null
