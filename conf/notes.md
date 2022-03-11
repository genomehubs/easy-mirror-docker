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

docker run --rm \
    -u $UID:$GROUPS \
    --name easy-import-melitaea_cinxia_core_52_105_1 \
    --network genomehubs-network \
    -v ~/easy-mirror-docker/conf:/import/conf \
    -e DATABASE=melitaea_cinxia_core_52_105_1 \
    -e FLAGS="-i" \
    genomehubs/easy-import:19.05