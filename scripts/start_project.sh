#!/bin/bash

options=$(getopt -o pvr --long project,version,realms: -- "$@")
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
    --)
        shift
        break
        ;;
    esac
    shift
done

PROJECT="${PROJECT:-untitled}"
VERSION="${VERSION:-8.2.0}"

SQL_ROOT_PW="trinity_root"
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

echo "Starting auth database..."
docker run -dP --rm \
    --name $CONTAINER_PREFIX\_auth_db \
    --network $CONTAINER_PREFIX\_auth \
    --network-alias auth_db \
    --expose 3306 \
    -v $LOCAL_PROJECT_DIR/auth/db:/var/lib/mysql \
    mariadb:latest
echo "Waiting for auth database to be ready..."
docker run -it --rm \
    --network $CONTAINER_PREFIX\_auth \
    mariadb:latest bash -c "while ! mysqladmin ping -hauth_db --silent; do sleep 1; done"
echo "Starting auth server..."
case $VERSION in 
    "8.2.0")
        port_bnet=$(cat $LOCAL_PROJECT_DIR/auth/bnetserver.conf | grep -e '^BattlenetPort' | awk '{print $3}');
        port_rest=$(cat $LOCAL_PROJECT_DIR/auth/bnetserver.conf | grep -e '^LoginREST\.Port' | awk '{print $3}');
        docker run -dP --rm \
            --name $CONTAINER_PREFIX\_auth \
            --network $CONTAINER_PREFIX\_auth \
            --network-alias auth \
            -p $port_bnet\:$port_bnet \
            -p $port_rest\:$port_rest \
            -v $LOCAL_PROJECT_DIR/server/bin:/opt/trinitycore/bin \
            -v $LOCAL_PROJECT_DIR/server/lib:/opt/trinitycore/lib \
            -v $LOCAL_PROJECT_DIR/auth/bnetserver.conf:/opt/trinitycore/etc/bnetserver.conf \
            -v $LOCAL_PROJECT_DIR/auth/logs:/opt/trinitycore/logs \
            trinitycore:universal bash -c "
                /opt/trinitycore/bin/bnetserver
            ";
        echo "";
        echo "Bnetserver is running on port $port_bnet";
        echo "";
		;;
    "3.3.5")
        port_auth=$(cat $LOCAL_PROJECT_DIR/auth/authserver.conf | grep -e '^RealmServerPort' | awk '{print $3}');
        docker run -dP --rm \
            --name $CONTAINER_PREFIX\_auth \
            --network $CONTAINER_PREFIX\_auth \
            --network-alias auth \
            -p $port_auth\:$port_auth \
            -v $LOCAL_PROJECT_DIR/server/bin:/opt/trinitycore/bin \
            -v $LOCAL_PROJECT_DIR/server/lib:/opt/trinitycore/lib \
            -v $LOCAL_PROJECT_DIR/auth/authserver.conf:/opt/trinitycore/etc/authserver.conf \
            -v $LOCAL_PROJECT_DIR/auth/logs:/opt/trinitycore/logs \
            trinitycore:universal bash -c "
                /opt/trinitycore/bin/authserver
            ";
        echo "";
        echo "Authserver is running on port $port_auth";
        echo "";
        ;;
esac

if [ "$REALMS" == "" ]; then
	readarray -t REALMS < <(find $LOCAL_PROJECT_DIR/realms -maxdepth 1 -type d -printf '%P\n')
fi
for realm in ${REALMS[@]}; do
    LOCAL_REALM_DIR=$LOCAL_PROJECT_DIR/realms/$realm
    realm_id=$(docker run -it --rm \
        --network $CONTAINER_PREFIX\_auth \
        mariadb:latest mysql -hauth_db -P3306 -uroot -p$SQL_ROOT_PW -Dauth -N -e "
            SELECT id FROM realmlist WHERE name = '$realm';
        " | sed 's/\-//g' | sed 's/\+//g' | sed 's/[[:space:]]//g')
	realm_id=${realm_id//|}
	
    if [ -z "$realm_id" ]; then
        docker run -it --rm \
            --network $CONTAINER_PREFIX\_auth \
            mariadb:latest mysql -hauth_db -P3306 -uroot -p$SQL_ROOT_PW -Dauth -N -e "
                INSERT INTO realmlist (name, flag, timezone) VALUES ('$realm', 0, 2);
            "
        realm_id=$(docker run -it --rm \
            --network $CONTAINER_PREFIX\_auth \
            mariadb:latest mysql -hauth_db -P3306 -uroot -p$SQL_ROOT_PW -Dauth -N -e "
                SELECT id FROM realmlist WHERE name = '$realm';
            " | sed 's/\-//g' | sed 's/\+//g' | sed 's/[[:space:]]//g')
		realm_id=${realm_id//|}
    fi
	realm_id=$(echo $realm_id | sed ':a;N;$!ba;s/\n/ /g')

    echo "Starting $realm realm database..."
    docker run -dP --rm \
        --name $CONTAINER_PREFIX\_$realm\_db \
        --network $CONTAINER_PREFIX\_$realm \
        --network-alias realm_db \
        -v $LOCAL_REALM_DIR/db:/var/lib/mysql \
        mariadb:latest

    echo "Waiting for $realm realm database to be ready..."
    docker run -it --rm \
        --network $CONTAINER_PREFIX\_$realm \
        mariadb:latest bash -c "while ! mysqladmin ping -hrealm_db --silent; do sleep 1; done"

    echo "Configuring ports..."
    docker run -dP --rm \
        --name $CONTAINER_PREFIX\_portcheck \
        --expose 10000 \
        --expose 10001 \
        trinitycore:universal sleep 30
    while [ -z "$docker_inspect" ]; do 
        docker_inspect=($(docker inspect --format='{{range $conf := .NetworkSettings.Ports}} {{(index $conf 0).HostPort}} {{end}}' $CONTAINER_PREFIX\_portcheck))
    done
    port_world=${docker_inspect[0]}
    port_instance=${docker_inspect[1]}
    docker kill $CONTAINER_PREFIX\_portcheck
	unset docker_inspect

    echo "Starting $realm realm server..."
    docker run -dP --rm \
        --name $CONTAINER_PREFIX\_$realm \
        --network $CONTAINER_PREFIX\_$realm \
        --network-alias $realm\_world \
        --expose 3443 \
        --expose 7878 \
        -p $port_world\:$port_world \
        -p $port_instance\:$port_instance \
        -v $LOCAL_PROJECT_DIR/server/bin:/opt/trinitycore/bin \
        -v $LOCAL_PROJECT_DIR/server/lib:/opt/trinitycore/lib \
        -v $LOCAL_PROJECT_DIR/source:/src/trinitycore \
        -v $LOCAL_REALM_DIR/worldserver.conf:/opt/trinitycore/temp/worldserver.conf \
        -v $LOCAL_REALM_DIR/logs:/opt/trinitycore/logs \
        trinitycore:universal bash -c "
            mkdir -p /opt/trinitycore/etc;
            cp /opt/trinitycore/temp/worldserver.conf /opt/trinitycore/etc/worldserver.conf;
            sed -i 's/^RealmID.*\$/RealmID \= $realm_id/g' /opt/trinitycore/etc/worldserver.conf;
            sed -i 's/^WorldServerPort.*\$/WorldServerPort \= $port_world/g' /opt/trinitycore/etc/worldserver.conf;
            sed -i 's/^InstanceServerPort.*\$/InstanceServerPort \= $port_instance/g' /opt/trinitycore/etc/worldserver.conf;
            sleep 5; 
            /opt/trinitycore/bin/worldserver
        "
    echo "Connecting $realm realm server to auth network..."
    docker network connect $CONTAINER_PREFIX\_auth $CONTAINER_PREFIX\_$realm
	
    while [ -z "$docker_inspect" ]; do 
        docker_inspect=($(docker inspect --format='{{range $conf := .NetworkSettings.Ports}} {{(index $conf 0).HostPort}} {{end}}' $CONTAINER_PREFIX\_$realm))
    done
    port_ra=${docker_inspect[0]}
	unset docker_inspect
    echo ""
    echo "Realm #$realm_id, $realm, is running on port $port_world"
    echo "    RA Telnet port is $port_ra"
    echo ""
    docker run -it --rm \
        --network $CONTAINER_PREFIX\_auth \
        mariadb:latest mysql -hauth_db -P3306 -uroot -p$SQL_ROOT_PW -Dauth -N -e "
            UPDATE realmlist SET port = $port_world WHERE id = $realm_id;
        "
done
