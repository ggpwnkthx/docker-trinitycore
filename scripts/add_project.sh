#!/bin/bash

options=$(getopt -o pvrd --long project,version,realms,development: -- "$@")
[ $? -eq 0 ] || { 
    echo "Incorrect options provided"
    exit 1
}
eval set -- "$options"
while true; do
    case "$1" in
    -p | --project )
        shift;
        PROJECT=$1;
		;;
    -v | --version )
        shift;
        VERSION=$1;
        ;;
    -r | --realms )
        shift;
        REALMS=($(echo $1 | sed 's/,/ /g'));
        ;;
    -d | --development )
        DEVELOPMENT=true;
        ;;
    --)
        shift
        break
        ;;
    esac
    shift
done
PROJECT="${PROJECT:-untitled}"
VERSION="${VERSION:-8.2.0}"
REALMS="${REALMS:-Trinity}"

SCRIPTROOT=../"$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/.."
SOURCE_DIR=source/$VERSION
LOCAL_SOURCE_DIR=$SCRIPTROOT/$SOURCE_DIR
BUILD_DIR=build/$VERSION
LOCAL_BUILD_DIR=$SCRIPTROOT/$BUILD_DIR
CLIENT_DIR=clients/$VERSION
LOCAL_CLIENT_DIR=$SCRIPTROOT/$CLIENT_DIR
PROJECT_DIR=projects/$PROJECT/$VERSION
LOCAL_PROJECT_DIR=$SCRIPTROOT/$PROJECT_DIR

CONTAINER_PREFIX=trinitycore_$PROJECT\_$VERSION
REALMS=($(echo $REALMS | sed 's/,/ /g'))

# Create directories and copy data if it doesnt already exist
echo "Copying binaries..."
data=(bin lib)
for dir in ${data[@]}; do
    if [ ! -d $LOCAL_PROJECT_DIR/server/$dir ]; then
        docker run -it --rm \
            -v $SCRIPTROOT\:/prepare \
            trinitycore:universal bash -c "
                mkdir -p /prepare/$PROJECT_DIR/server/$dir
                rsync -ah --info=progress2 /prepare/$BUILD_DIR/$dir/ /prepare/$PROJECT_DIR/server/$dir
            "
    fi
done
# Copy the extracted and generated data to the realm directory
data=(dbc maps gt vmaps mmaps)
for dir in ${data[@]}; do
    if [ -d $LOCAL_CLIENT_DIR/$dir ] && [ ! -d $LOCAL_PROJECT_DIR/server/bin/data/$dir ]; then
        echo "Copying $dir data..."
        docker run -it --rm \
            -v $SCRIPTROOT\:/prepare \
            trinitycore:universal bash -c "
                mkdir -p /prepare/$PROJECT_DIR/server/bin/data/$dir
                rsync -ah --info=progress2 /prepare/$CLIENT_DIR/$dir/ /prepare/$PROJECT_DIR/server/bin/data/$dir
            "
    fi
done
if [ ! -d $LOCAL_PROJECT_DIR/auth/db ]; then
    echo "Copying database for authserver..."
    docker run -it --rm \
        -v $SCRIPTROOT\:/prepare \
        trinitycore:universal bash -c "
            mkdir -p /prepare/$PROJECT_DIR/auth/db;
            rsync -ah --info=progress2 /prepare/$BUILD_DIR/db/auth/ /prepare/$PROJECT_DIR/auth/db;
            cp /prepare/$BUILD_DIR/etc/authserver.conf /prepare/$PROJECT_DIR/auth/authserver.conf;
            cp /prepare/$BUILD_DIR/etc/bnetserver.conf /prepare/$PROJECT_DIR/auth/bnetserver.conf;
            mkdir -p /prepare/$PROJECT_DIR/auth/logs;
        "
fi
docker network create $CONTAINER_PREFIX\_auth
for realm in ${REALMS[@]}; do
    REALM_DIR=$PROJECT_DIR/realms/$realm
    LOCAL_REALM_DIR=$SCRIPTROOT/$REALM_DIR
    docker network create $CONTAINER_PREFIX\_$realm
    if [ ! -d $LOCAL_REALM_DIR/db ]; then
		echo "Copying $realm realm databases..."
        docker run -it --rm \
            -v $SCRIPTROOT\:/prepare \
            trinitycore:universal bash -c "
                mkdir -p /prepare/$REALM_DIR/db;
                rsync -ah --info=progress2 /prepare/$BUILD_DIR/db/realm/ /prepare/$REALM_DIR/db;
                cp /prepare/$BUILD_DIR/etc/worldserver.conf /prepare/$REALM_DIR/worldserver.conf;
                chmod 777 /prepare/$REALM_DIR/worldserver.conf;
                mkdir -p /prepare/$REALM_DIR/logs;
            "
    fi
done
# Copy source data
echo "Copying any necessary source data..."
if [ $DEVELOPMENT ]; then
    echo "Copying source code..."
    docker run -it --rm \
        -v $SCRIPTROOT\:/prepare \
        trinitycore:universal bash -c "
            if [ ! -d $REALM_DIR/source/.git ]; then 
                rsync -ah --info=progress2 /prepare/$SOURCE_DIR/ $REALM_DIR/source; 
            fi;
    "
fi
if [ ! -d $LOCAL_PROJECT_DIR/source/sql ]; then
    echo "Copying source SQL data..."
    docker run -it --rm \
        -v $SCRIPTROOT\:/prepare \
        trinitycore:universal bash -c "
            mkdir -p /prepare/$PROJECT_DIR/source/sql;
            rsync -ah --info=progress2 /prepare/$BUILD_DIR/sql/ /prepare/$PROJECT_DIR/source/sql;
        "
fi

# Add NUFAD Instance
if [ ! -d $LOCAL_PROJECT_DIR/admin ]; then
    echo "Preparing admin interface..."
    docker run -it --rm \
        -v $SCRIPTROOT\:/prepare \
        trinitycore:universal bash -c "
            mkdir -p /prepare/$PROJECT_DIR/admin;
            rsync -ah  --info=progress2 /prepare/$BUILD_DIR/nufad/ /prepare/$PROJECT_DIR/admin;
        "
    # Create SSL Certificate
    docker run -it --rm \
        -v $SCRIPTROOT\:/prepare \
        trinitycore:universal bash -c "
            mkdir -p /prepare/$PROJECT_DIR/admin/certs;
            openssl genrsa -out /prepare/$PROJECT_DIR/admin/certs/ssl.pass.key 2048;
            openssl rsa -in /prepare/$PROJECT_DIR/admin/certs/ssl.pass.key -out /prepare/$PROJECT_DIR/admin/certs/ssl.key;
            rm /prepare/$PROJECT_DIR/admin/certs/ssl.pass.key;
            openssl req -new -key /prepare/$PROJECT_DIR/admin/certs/ssl.key -out /prepare/$PROJECT_DIR/admin/certs/ssl.csr -subj \"/C=NA/ST=NA/\";
	        openssl x509 -req -days 7120 -in /prepare/$PROJECT_DIR/admin/certs/ssl.csr -signkey /prepare/$PROJECT_DIR/admin/certs/ssl.key -out /prepare/$PROJECT_DIR/admin/certs/ssl.crt;
        "
fi
