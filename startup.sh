#!/bin/bash

/ensembl/scripts/update.sh /ensembl/conf/setup.ini &> /ensembl/logs/update.log
/ensembl/scripts/reload.sh /ensembl/conf/setup.ini &> /ensembl/logs/reload.log
tail -f /dev/null
