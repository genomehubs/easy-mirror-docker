#!/bin/bash

if [ -s "/conf/database.ini" ]; then
  /ensembl/scripts/database.sh /conf/database.ini &> /ensembl/logs/database.log
fi
if [ -s "/conf/setup.ini" ]; then
  /ensembl/scripts/update_only.sh /conf/setup.ini &> /ensembl/logs/update.log
fi
/ensembl/scripts/reload.sh &> /ensembl/logs/reload.log
tail -f /dev/null
