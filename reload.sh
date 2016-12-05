#!/bin/bash

# check script was called correctly
INI=$1
if [ -z $INI ]; then
  echo "Usage: './reload-ensemblcode.sh <filename.ini>'\n";
  exit 1
fi

# set directory names
SERVER_ROOT=/ensembl

# stop server
$SERVER_ROOT/ensembl-webcode/ctrl_scripts/stop_server

# remove packed config files
if [ -e $SERVER_ROOT/ensembl-webcode/conf/config.packed ]; then
  rm $SERVER_ROOT/ensembl-webcode/conf/config.packed
  rm -r $SERVER_ROOT/ensembl-webcode/conf/packed
fi

# start server
$SERVER_ROOT/ensembl-webcode/ctrl_scripts/start_server

# test whether site is working, restart if not
HTTP_PORT=8080
COUNT=0
URL=http://localhost:$HTTP_PORT/i/placeholder.png
while [ $COUNT -lt 5 ]; do
  if curl --output /dev/null --silent --head --fail "$URL"; then
    break
  else
    if [ $COUNT -lt 4 ]; then
      echo "WARNING: unable to resolve URL $URL, restarting server."
      $SERVER_ROOT/ensembl-webcode/ctrl_scripts/restart_server
    else
      echo "ERROR: failed to start server in 5 attempts."
    fi
  fi
  let COUNT=COUNT+1
done

