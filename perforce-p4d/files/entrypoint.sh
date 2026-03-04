#!/bin/bash

init.sh
exec /usr/bin/tail -F "$P4ROOT/logs/log"
