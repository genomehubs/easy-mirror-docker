#!/bin/bash

# set directory names
SERVER_ROOT=/ensembl
HTTP_PORT=8080
HOSTNAME=$(hostname)

# create directory for log files
mkdir -p $SERVER_ROOT/logs/$HOSTNAME-ensembl

# stop server
$SERVER_ROOT/ensembl-webcode/ctrl_scripts/stop_server

# remove packed config files
if [ -d $SERVER_ROOT/conf/packed ]; then
  rm -r $SERVER_ROOT/conf/*packed*
fi

# start server
$SERVER_ROOT/ensembl-webcode/ctrl_scripts/start_server

# test whether site is working, restart if not
COUNT=0
URL=http://localhost:$HTTP_PORT/i/placeholder.png
while [ $COUNT -lt 7 ]; do
  if curl --output /dev/null --silent --head --fail "$URL"; then
    break
  else
    if [ $COUNT -lt 6 ]; then
      echo "WARNING: unable to resolve URL $URL, restarting server."
      $SERVER_ROOT/ensembl-webcode/ctrl_scripts/restart_server
    else
      echo "ERROR: failed to start server in 6 attempts."
    fi
  fi
  let COUNT=COUNT+1
done

