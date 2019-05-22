#!/bin/bash

# check script was called correctly
INI=$1
if [ -z $INI ]; then
  echo "Usage: './setup-databases.sh <filename.ini>'\n";
  exit 1
fi

# set database users and passwords from ini file
DB_ROOT_USER=$(awk -F "=" '/DB_ROOT_USER/ {print $2}' $INI | tr -d ' ')
DB_ROOT_PASSWORD=$(awk -F "=" '/DB_ROOT_PASSWORD/ {print $2}' $INI | tr -d ' ')
DB_HOST=$(awk -F "=" '/DB_HOST/ {print $2}' $INI | tr -d ' ')
if [ $DB_HOST = "localhost" ]; then
  DB_HOST=$MYSQL_SERVER_PORT_3306_TCP_ADDR
fi
DB_PORT=$(awk -F "=" '/DB_PORT/ {print $2}' $INI | tr -d ' ')
DB_USER=$(awk -F "=" '/DB_USER/ {print $2}' $INI | tr -d ' ')
DB_PASS=$(awk -F "=" '/DB_PASS/ {print $2}' $INI | tr -d ' ')
DB_SESSION_USER=$(awk -F "=" '/DB_SESSION_USER/ {print $2}' $INI | tr -d ' ')
DB_SESSION_PASS=$(awk -F "=" '/DB_SESSION_PASS/ {print $2}' $INI | tr -d ' ')
DB_SESSION_NAME=$(awk -F "=" '/DB_SESSION_NAME/ {print $2}' $INI | tr -d ' ')
DB_IMPORT_USER=$(awk -F "=" '/DB_IMPORT_USER/ {print $2}' $INI | tr -d ' ')
DB_IMPORT_PASS=$(awk -F "=" '/DB_IMPORT_PASS/ {print $2}' $INI | tr -d ' ')
DB_IMPORT_HOST=$(awk -F "=" '/DB_IMPORT_HOST/ {print $2}' $INI | tr -d ' ')

ROOT_CONNECT="mysql -u$DB_ROOT_USER -p$DB_ROOT_PASSWORD -h$DB_HOST -P$DB_PORT"
IMPORT_CONNECT="mysqlimport -u$DB_ROOT_USER -p$DB_ROOT_PASSWORD -h$DB_HOST -P$DB_PORT"

# test whether we can connect and throw error if not
$ROOT_CONNECT -e "" &> /dev/null;
if ! [ $? -eq 0 ]; then
    printf "ERROR: Unable to connect to mysql server as root.\n       Check connection settings in $INI\n"
    exit 1;
fi

# set website host variable to determine where the db will be accessed from
ENSEMBL_WEBSITE_HOST=$(awk -F "=" '/ENSEMBL_WEBSITE_HOST/ {print $2}' $INI | tr -d ' ')
if [ -z $ENSEMBL_WEBSITE_HOST ]; then
  # no host set, assume access allowed from anywhere
  ENSEMBL_WEBSITE_HOST=%
fi

# create database users and grant privileges
if [ -z $DB_SESSION_USER  ]; then
  printf "ERROR: No DB_SESSION_USER specified.\n       Unable to create $DB_SESSION_NAME database\n"
  exit 1;
fi
if ! [ -z $DB_IMPORT_USER ]; then
  IMPORT_USER_CREATE="GRANT ALL ON *.* TO '$DB_IMPORT_USER'@'$ENSEMBL_WEBSITE_HOST' IDENTIFIED BY '$DB_IMPORT_PASS';"
fi
SESSION_USER_CREATE="GRANT SELECT, INSERT, UPDATE, DELETE, LOCK TABLES ON $DB_SESSION_NAME.* TO '$DB_SESSION_USER'@'$ENSEMBL_WEBSITE_HOST' IDENTIFIED BY '$DB_SESSION_PASS';"
if ! [ -z $DB_USER  ]; then
  DB_USER_CREATE="GRANT SELECT ON *.* TO '$DB_USER'@'$ENSEMBL_WEBSITE_HOST'"
  if ! [ -z $DB_PASS ]; then
    DB_USER_CREATE="$DB_USER_CREATE IDENTIFIED BY '$DB_PASS'"
  fi
  DB_USER_CREATE="$DB_USER_CREATE;"
fi
$ROOT_CONNECT -e "$IMPORT_USER_CREATE$SESSION_USER_CREATE$DB_USER_CREATE"

function load_db(){
  #load_db <remote_url> <db_name> [overwrite_flag]

  URL_EXISTS=1
  REMOTE=$1
  OLDIFS=$IFS
  IFS="|" read DB NAME <<< "$2"
  IFS=$OLDIFS
  if [ -z $NAME ]; then
    NAME=$DB
  fi
  FLAG=$3
  echo Working on $REMOTE/$DB as $NAME

  if [ -z $FLAG ]; then
    # don't overwrite database if it already exists
    $ROOT_CONNECT -e "USE $NAME" &> /dev/null
    if [ $? -eq 0 ]; then
      echo "  $NAME exists, not overwriting"
      return
    fi
  fi

  if curl --output /dev/null --silent --head --fail "$REMOTE/$DB/$DB.sql.gz"; then
    echo " URL exists"
  else
    URL_EXISTS=
    echo "  no dump available"
    return
  fi

  # create local database
  $ROOT_CONNECT -e "DROP DATABASE IF EXISTS $NAME; CREATE DATABASE $NAME;"

  # fetch and unzip sql/data
  PROTOCOL="$(echo $REMOTE | grep :// | sed -e's,^\(.*://\).*,\1,g')"
  URL="$(echo ${REMOTE/$PROTOCOL/})"
  wget -q -r $REMOTE/$DB
  mv $URL/* ./
  gunzip $DB/*sql.gz

  # load sql into database
  $ROOT_CONNECT $NAME < $DB/$DB.sql
  # load data into database

  if ls $DB/*.txt.gz 1> /dev/null 2>&1; then
    for ZIPPED_FILE in $DB/*.txt.gz
    do
      gunzip $ZIPPED_FILE
      FILE=${ZIPPED_FILE%.*}
      $IMPORT_CONNECT --fields_escaped_by=\\\\ $NAME -L $FILE
      rm $FILE
    done
  fi
  # remove remaining downloaded data
  rm -r $DB

  # patch database to new release if appropriate
  if [ "$DB" != "$NAME" ]; then
    FROM=$(echo $DB | awk -F '_' '{print $NF}')
    TO=$(echo $NAME | awk -F '_' '{print $NF}')
    TYPE=$(echo $NAME | awk -F '_' '{print $ (NF-1)}')
    if [[ $DB =~ _([a-z]+)_[0-9]+_([0-9]+)_[0-9]+ ]]; then
      FROM=${BASH_REMATCH[2]}
      TO=$(echo $NAME | awk -F '_' '{print $ (NF-1)}')
      TYPE=${BASH_REMATCH[1]}
    elif [[ $DB =~ _([a-z]+)_[0-9]+_([0-9]+) ]]; then
      FROM=${BASH_REMATCH[2]}
      TYPE=${BASH_REMATCH[1]}
    fi
    CMD="echo y | /ensembl/ensembl/misc-scripts/schema_patcher.pl \
         --host $DB_HOST \
         --port $DB_PORT \
         --user $DB_ROOT_USER \
         --pass $DB_ROOT_PASSWORD \
         --type $TYPE \
         --from $FROM \
         --release $TO \
         --verbose \
         --interactive 0 \
         --database $NAME"
    eval $CMD
  fi
}

# move to /tmp while downloading files
CURRENTDIR=`pwd`
cd /tmp

# fetch and load ensembl website databases
ENSEMBL_DB_REPLACE=$(awk -F "=" '/ENSEMBL_DB_REPLACE/ {print $2}' $INI | tr -d ' ')
ENSEMBL_DB_URL=$(awk -F "=" '/ENSEMBL_DB_URL/ {print $2}' $INI | tr -d ' ')
ENSEMBL_DBS=$(perl -lne '$s.=$_;END{if ($s=~m/ENSEMBL_DBS\s*=\s*\[\s*(.+?)\s*\]/){print $1}}' $INI)
if ! [ -z $ENSEMBL_DB_URL ]; then
  for DB in $ENSEMBL_DBS
  do
    load_db $ENSEMBL_DB_URL $DB $ENSEMBL_DB_REPLACE
    if [ -z $URL_EXISTS ]; then
      echo "ERROR: Unable to find database dump at $ENSEMBL_DB_URL/$DB"
    fi
  done
fi

# fetch and load EnsemblGenomes databases
EG_DB_REPLACE=$(awk -F "=" '/EG_DB_REPLACE/ {print $2}' $INI | tr -d ' ')
EG_DB_URL=$(awk -F "=" '/EG_DB_URL/ {print $2}' $INI | tr -d ' ')
EG_DBS=$(perl -lne '$s.=$_;END{if ($s=~m/EG_DBS\s*=\s*\[\s*(.+?)\s*\]/){print $1}}' $INI)
if ! [ -z $EG_DB_URL ]; then
  for DB in $EG_DBS
  do
    load_db $EG_DB_URL $DB $EG_DB_REPLACE
    if [ -z $URL_EXISTS ]; then
      echo "ERROR: Unable to find database dump at $EG_DB_URL/$DB"
    fi
  done
fi

# fetch and load species databases
SPECIES_DB_REPLACE=$(awk -F "=" '/SPECIES_DB_REPLACE/ {print $2}' $INI | tr -d ' ')
SPECIES_DB_AUTO_EXPAND=$(awk -F "=" '/SPECIES_DB_AUTO_EXPAND/ {print $2}' $INI | tr -d '[' | tr -d ']')
SPECIES_DB_URL=$(awk -F "=" '/SPECIES_DB_URL/ {print $2}' $INI | tr -d ' ')
SPECIES_DBS=$(perl -lne '$s.=$_;END{if ($s=~m/SPECIES_DBS\s*=\s*\[\s*(.+?)\s*\]/){print $1}}' $INI)
if ! [ -z $SPECIES_DB_URL ]; then
  for DB in $SPECIES_DBS
  do
    load_db $SPECIES_DB_URL $DB $SPECIES_DB_REPLACE
    if [ -z $URL_EXISTS ]; then
      echo "ERROR: Unable to find database dump at $SPECIES_DB_URL/$DB"
    fi
    if ! [ -z "$SPECIES_DB_AUTO_EXPAND" ]; then
      # auto-expand core with DB types in list
      for DB_TYPE in $SPECIES_DB_AUTO_EXPAND
      do
        NEW_DB=${DB/_core_/_${DB_TYPE}_}
        # attempt to fetch and load db
        load_db $SPECIES_DB_URL $NEW_DB $SPECIES_DB_REPLACE
      done
    fi
  done
fi

# fetch and load any other databases
MISC_DB_REPLACE=$(awk -F "=" '/MISC_DB_REPLACE/ {print $2}' $INI | tr -d ' ')
MISC_DB_URL=$(awk -F "=" '/MISC_DB_URL/ {print $2}' $INI | tr -d ' ')
MISC_DBS=$(awk -F "=" '/MISC_DBS/ {print $2}' $INI | tr -d '[' | tr -d ']')
MISC_DBS=$(perl -lne '$s.=$_;END{if ($s=~m/MISC_DBS\s*=\s*\[\s*(.+?)\s*\]/){print $1}}' $INI)
if ! [ -z $MISC_DB_URL ]; then
  for DB in $MISC_DBS
  do
    load_db $MISC_DB_URL $DB $MISC_DB_REPLACE
    if [ -z $URL_EXISTS ]; then
      echo "ERROR: Unable to find database dump at $MISC_DB_URL/$DB"
    fi
  done
fi

cd $CURRENTDIR

