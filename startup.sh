#!/bin/bash

if [ -s "/ensembl/conf/database.ini" ]; then
  /ensembl/scripts/database.sh /ensembl/conf/database.ini &> /ensembl/logs/dataabse.log
fi
if [ -s "/ensembl/conf/setup.ini" ]; then
  /ensembl/scripts/update.sh /ensembl/conf/setup.ini &> /ensembl/logs/update.log
fi
/ensembl/scripts/reload.sh &> /ensembl/logs/reload.log
tail -f /dev/null
