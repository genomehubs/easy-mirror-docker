docker network create genomehubs-network

docker run -d \
    --name genomehubs-mysql \
    --network genomehubs-network \
    -v ~/genomehubs/mysql/data:/var/lib/mysql \
    -e MYSQL_ROOT_PASSWORD=CHANGEME \
    -e MYSQL_ROOT_HOST='172.16.0.0/255.240.0.0' \
    -p 3306:3306 \
    mysql/mysql-server:5.5

docker run -d \
    --name genomehubs-ensembl \
    -v ~/easy-mirror-docker/conf:/conf:ro \
    --network genomehubs-network \
    -p 8080:8080 \
    genomehubs/easy-mirror-docker:latest

docker rm -f genomehubs-search && docker run -d              --name genomehubs-search -e SEARCH_DB_NAME='genomehubs_search_52_105'              --network genomehubs-network              -p 8884:8080              -v /home/ubuntu/search-docker/lbsearch:/var/www/search.genomehubs.org/cgi-bin/lbsearch genomehubs/search:latest

docker run --rm \
    -u $UID:$GROUPS \
    --name easy-import-melitaea_cinxia_core_52_105_1 \
    --network genomehubs-network \
    -v ~/easy-mirror-docker/conf:/import/conf \
    -v ~/easy-import:/ensembl/easy-import \
    -e DATABASE=melitaea_cinxia_core_52_105_1 \
    -e FLAGS="-i" \
    genomehubs/easy-import:latest