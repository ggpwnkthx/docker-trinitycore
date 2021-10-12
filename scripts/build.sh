#!/bin/bash

options=$(getopt -o br --long branch,repo: -- "$@")
[ $? -eq 0 ] || { 
    echo "Incorrect options provided"
    exit 1
}
eval set -- "$options"
while true; do
    case "$1" in
    -b | --branch )
        shift;
        BRANCH=$1;
		;;
    -r | --repo )
        shift;
        REPO=$1;
        ;;
    --)
        shift
        break
        ;;
    esac
    shift
done

BRANCH="${BRANCH:-master}"
REPO="${REPO:-git://github.com/TrinityCore/TrinityCore.git}"

if [ "$BRANCH" == "master" ]; then
	VERSION="9.1.0"
else
	VERSION=$BRANCH
fi
SQL_ROOT_PW="trinity_root"

SCRIPTROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/.."
SOURCE_DIR=source/$VERSION
LOCAL_SOURCE_DIR=$SCRIPTROOT/$SOURCE_DIR
BUILD_DIR=build/$VERSION
LOCAL_BUILD_DIR=$SCRIPTROOT/$BUILD_DIR
CLIENT_DIR=clients/$VERSION
LOCAL_CLIENT_DIR=$SCRIPTROOT/$CLIENT_DIR

# Build compiler container
echo "Building universal TrinityCore image..."
cd $SCRIPTROOT
docker build -t trinitycore:universal -f ./docker/Dockerfile_universal ./docker

# Create directories
docker run -it --rm \
    -v $SCRIPTROOT\:/prepare \
    trinitycore:universal bash -c "
        mkdir -p /prepare/$SOURCE_DIR; 
        mkdir -p /prepare/$BUILD_DIR/bin; 
        mkdir -p /prepare/$BUILD_DIR/db/base;
    "

# Download source code
docker run -it --rm \
    -v $LOCAL_SOURCE_DIR\:/src/trinitycore \
    trinitycore:universal bash -c "
        git clone -b $BRANCH $REPO /src/trinitycore;
        mkdir -p /src/trinitycore/build;
        cd /src/trinitycore; 
        git pull;
    "
if [ "$VERSION" == "3.3.5" ]; then
	# Download Eluna
    docker run -it --rm \
        -v $LOCAL_SOURCE_DIR\:/src/trinitycore \
        trinitycore:universal bash -c "
            cd /src/trinitycore;
            git pull --recurse-submodules https://github.com/ElunaLuaEngine/ElunaTrinityWotlk.git;
            git submodule init;
            git submodule update;
            git remote add ElunaTrinityWotlk https://github.com/ElunaLuaEngine/ElunaTrinityWotlk.git;
        "
fi

# Build
docker run -it --rm \
    -v $LOCAL_SOURCE_DIR\:/src/trinitycore \
    -v $LOCAL_BUILD_DIR\:/opt/trinitycore \
    trinitycore:universal bash -c "
        cd /src/trinitycore/build; 
        cmake ../ \
            -DCMAKE_INSTALL_PREFIX=/opt/trinitycore \
            -DCONF_DIR=/opt/trinitycore/etc \
            -DLIBSDIR=/opt/trinitycore/lib \
            -DSCRIPTS=dynamic \
            -DWITH_WARNINGS=1;
        make -j $(nproc);
        make install;
    "
# Rename config files
docker run -it --rm \
    -v $SCRIPTROOT\:/prepare \
    trinitycore:universal bash -c "
        cp /prepare/$BUILD_DIR/etc/worldserver.conf.dist /prepare/$BUILD_DIR/etc/worldserver.conf;
        cp /prepare/$BUILD_DIR/etc/authserver.conf.dist /prepare/$BUILD_DIR/etc/authserver.conf;
        cp /prepare/$BUILD_DIR/etc/bnetserver.conf.dist /prepare/$BUILD_DIR/etc/bnetserver.conf;
    "

# Get lastest releases of world database
rel_ver=${VERSION//.}
world_db=($(docker run -it --rm trinitycore:universal bash -c "curl -s https://api.github.com/repos/TrinityCore/TrinityCore/releases | grep browser_download_url | awk '{print \$2}' | grep TDB$rel_ver"))
world_db=${world_db[0]//\"}
world_db=${world_db::-1}
docker run -it --rm \
    -v $LOCAL_SOURCE_DIR\:/src/trinitycore \
    -v $LOCAL_BUILD_DIR\:/opt/trinitycore \
    trinitycore:universal bash -c "
        wget $world_db -O /src/trinitycore/sql/base/world_database.7z; 
        cd /src/trinitycore/sql/base/; 
        7za e world_database.7z; 
        rm world_database.7z; 
        if [ -f world_database.sql ]; then rm world_database.sql; fi;
        mv TDB_full_world*.sql world_database.sql; 
        if [ -f hotfixes_database.sql ]; then rm hotfixes_database.sql; fi;
        mv TDB_full_hotfixes*.sql hotfixes_database.sql; 
        mkdir -p /opt/trinitycore/sql/custom;
        rsync -ah --info=progress2 /src/trinitycore/sql/custom/ /opt/trinitycore/sql/custom;
        mkdir -p /opt/trinitycore/sql/updates;
        rsync -ah --info=progress2 /src/trinitycore/sql/updates/ /opt/trinitycore/sql/updates;
    "

# Extract maps from game client
docker run -it --rm \
	-v $LOCAL_BUILD_DIR\:/opt/trinitycore \
	-v $LOCAL_CLIENT_DIR\:/opt/wow \
	trinitycore:universal bash -c "
		chmod +x /opt/trinitycore/bin/; 
		cd /opt/wow; 
		if [ ! -d /opt/wow/maps ]; then /opt/trinitycore/bin/mapextractor; fi;
		if [ ! -d /opt/wow/vmaps ]; then /opt/trinitycore/bin/vmap4extractor && mkdir /opt/wow/vmaps && /opt/trinitycore/bin/vmap4assembler Buildings vmaps; fi;
		if [ ! -d /opt/wow/mmaps ]; then mkdir /opt/wow/mmaps && /opt/trinitycore/bin/mmaps_generator; fi;
	"

# Fix configuration files
docker run -it --rm \
    -v $LOCAL_BUILD_DIR\:/opt/trinitycore \
    trinitycore:universal bash -c "
        sed -i 's/^LoginDatabaseInfo.*$/LoginDatabaseInfo  \= \"auth_db;3306;root;$SQL_ROOT_PW;auth\"/g' /opt/trinitycore/etc/*;
        sed -i 's/^WorldDatabaseInfo.*$/WorldDatabaseInfo  \= \"realm_db;3306;root;$SQL_ROOT_PW;world\"/g' /opt/trinitycore/etc/*;
        sed -i 's/^CharacterDatabaseInfo.*$/CharacterDatabaseInfo  \= \"realm_db;3306;root;$SQL_ROOT_PW;characters\"/g' /opt/trinitycore/etc/*;
        sed -i 's/^HotfixDatabaseInfo.*$/HotfixDatabaseInfo  \= \"realm_db;3306;root;$SQL_ROOT_PW;hotfixes\"/g' /opt/trinitycore/etc/*;
        sed -i 's/^CMakeCommand.*$/CMakeCommand  \= \\\"\/use\/bin\/cmake\\\"/g' /opt/trinitycore/etc/*;
        sed -i 's/^DataDir.*$/DataDir  \= \\\"\/opt\/trinitycore\/bin\/data\\\"/g' /opt/trinitycore/etc/*;
        sed -i 's/^LogsDir.*$/LogsDir  \= \\\"\/opt\/trinitycore\/logs\\\"/g' /opt/trinitycore/etc/*;
        sed -i 's/^SourceDirectory.*$/SourceDirectory  \= \\\"\/src\/trinitycore\\\"/g' /opt/trinitycore/etc/*;
        sed -i 's/^BuildDirectory.*$/BuildDirectory  \= \\\"\/src\/trinitycore\/build\\\"/g' /opt/trinitycore/etc/*;
        sed -i 's/^Console.Enable.*$/Console.Enable \= 1/g' /opt/trinitycore/etc/*;
        sed -i 's/^Ra.Enable.*$/Ra.Enable \= 1/g' /opt/trinitycore/etc/*;
        sed -i 's/^SOAP.Enable.*$/SOAP.Enable \= 1/g' /opt/trinitycore/etc/*;
        sed -i 's/^SOAP.IP.*$/SOAP.IP \= \\\"0.0.0.0\\\"/g' /opt/trinitycore/etc/*;
        sed -i 's/^Metric.Enable.*$/Metric.Enable \= 1/g' /opt/trinitycore/etc/*;
        sed -i 's/^CertificatesFile.*$/CertificatesFile \= \/opt\/trinitycore\/bin\/bnetserver.cert.pem/g' /opt/trinitycore/etc/*;
        sed -i 's/^PrivateKeyFile.*$/PrivateKeyFile \= \/opt\/trinitycore\/bin\/bnetserver.key.pem/g' /opt/trinitycore/etc/*;
    "

# Create docker network for database building
docker network create trinitycore_db_build_$VERSION

# Start clean database server to get baseline binary SQL files
SQL_HOST_ALIAS="trinitycore_db"
if [ ! -d $LOCAL_BUILD_DIR/db/base/mysql ]; then
    echo "Starting SQL service..."
    db_container=$(docker run -dP --rm \
        --network trinitycore_db_build_$VERSION \
        --network-alias $SQL_HOST_ALIAS \
        -e "MYSQL_ROOT_PASSWORD=$SQL_ROOT_PW" \
        -v $LOCAL_BUILD_DIR/db/base:/var/lib/mysql \
        mariadb:latest)
		
    # Wait for database to complete initilization
    echo "Waiting for SQL data to initialize..."
    docker run -it --rm \
        --network trinitycore_db_build_$VERSION \
        mariadb:latest bash -c "
            while ! mysqladmin ping -h$SQL_HOST_ALIAS --silent; do sleep 1; done;
        "
    docker kill $db_container
fi

if [ ! -d $LOCAL_BUILD_DIR/db/auth ]; then
	# Copy baseline and build auth database on top
    echo "Copying initial SQL data for auth..."
    docker run -it --rm \
        -v $SCRIPTROOT\:/prepare \
        trinitycore:universal bash -c "
            mkdir -p /prepare/$BUILD_DIR/db/auth; 
            rsync -ah  --info=progress2 /prepare/$BUILD_DIR/db/base/ /prepare/$BUILD_DIR/db/auth;
        "
    # Start auth database to get baseline auth binary SQL files
    echo "Starting auth SQL service..."
    db_container=$(docker run -dP --rm \
        --network trinitycore_db_build_$VERSION \
        --network-alias $SQL_HOST_ALIAS \
        -v $LOCAL_BUILD_DIR/db/auth:/var/lib/mysql \
        mariadb:latest)
    # Wait for database to complete initilization
    echo "Waiting for auth SQL to be ready..."
    docker run -it --rm \
        --network trinitycore_db_build_$VERSION \
        -v $LOCAL_SOURCE_DIR\:/src/trinitycore \
        mariadb:latest bash -c "
            while ! mysqladmin ping -h$SQL_HOST_ALIAS --silent; do sleep 1; done;
        "
    # Create auth db
    echo "Creating auth database..."
    docker run -it --rm \
        --network trinitycore_db_build_$VERSION \
        -v $LOCAL_SOURCE_DIR\:/src/trinitycore \
        mariadb:latest mysql -h"$SQL_HOST_ALIAS" -P3306 -uroot -p"$SQL_ROOT_PW" -e "
            CREATE DATABASE auth DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci ;
        "
    # Import schema
    echo "Importing auth schema..."
    docker run -it --rm \
        --network trinitycore_db_build_$VERSION \
        -v $LOCAL_SOURCE_DIR\:/src/trinitycore \
        mariadb:latest bash -c "
            cat /src/trinitycore/sql/base/auth_database.sql | mysql -h$SQL_HOST_ALIAS -P3306 -uroot -p$SQL_ROOT_PW -Dauth;
        "
    # Add admin account
    echo "Adding admin account..."
	case $VERSION in 
		"9.1.0")
            docker run -it --rm \
                --network trinitycore_db_build_$VERSION \
                -v $LOCAL_SOURCE_DIR\:/src/trinitycore \
                mariadb:latest mysql -h"$SQL_HOST_ALIAS" -P3306 -uroot -p"$SQL_ROOT_PW" -Dauth -e "
                    INSERT INTO battlenet_accounts (email, sha_pass_hash) VALUES ('@ADMIN', 'F00BE58CA64D719A2D32EB8E936738ABCE8871F4DEE31E85724C3D7AF769F145' );
                    INSERT INTO account (username,salt,verifier,email,reg_mail,battlenet_account,battlenet_index)
                    VALUES ('1#1', _binary 0xbc79f33212dc3c41c0402868ce45611c17b2ed5229d4422d4ba05e623788f711, _binary 0x0939d3b5bae1e98fe77f447bca34aeedbd59ddb6c6c7ad302e5f4feb6c9b7e5f, '@ADMIN', '@ADMIN', 1, 1);
                    INSERT INTO account_access (AccountID, SecurityLevel, RealmID) VALUES (1, 3, -1);
                ";;
		"3.3.5")
            docker run -it --rm \
                --network trinitycore_db_build_$VERSION \
                -v $LOCAL_SOURCE_DIR\:/src/trinitycore \
                mariadb:latest mysql -h"$SQL_HOST_ALIAS" -P3306 -uroot -p"$SQL_ROOT_PW" -Dauth -e "
                    INSERT INTO account (id, username, sha_pass_hash) VALUES (1, 'ADMIN', '8301316D0D8448A34FA6D0C6BF1CBFA2B4A1A93A') ; 
                    INSERT INTO account_access (id, gmlevel, RealmID) VALUES (1, 3, -1) ; 
                "
	esac
    docker kill $db_container
fi

if [ ! -d $LOCAL_BUILD_DIR/db/realm/world ]; then
	# Copy baseline and build world and character databases on top
    echo "Copying initial SQL data for realms..."
    docker run -it --rm \
        -v $SCRIPTROOT\:/prepare \
        trinitycore:universal bash -c "
            mkdir -p /prepare/$BUILD_DIR/db/realm; 
            rsync -ah  --info=progress2 /prepare/$BUILD_DIR/db/base/ /prepare/$BUILD_DIR/db/realm;
        "
    # Start realm database to get baseline auth binary SQL files
    echo "Starting realm SQL service..."
    db_container=$(docker run -dP --rm \
        --network trinitycore_db_build_$VERSION \
        --network-alias $SQL_HOST_ALIAS \
        -v $LOCAL_BUILD_DIR/db/realm:/var/lib/mysql \
        mariadb:latest)
    # Wait for database to complete initilization
    echo "Waiting for realm SQL to be ready..."
    docker run -it --rm \
        --network trinitycore_db_build_$VERSION \
        -v $LOCAL_SOURCE_DIR\:/src/trinitycore \
        mariadb:latest bash -c "
            while ! mysqladmin ping -h$SQL_HOST_ALIAS --silent; do sleep 1; done;
        "
    # Create character and world db
    echo "Creating characters and world databases..."
    docker run -it --rm \
        --network trinitycore_db_build_$VERSION \
        -v $LOCAL_SOURCE_DIR\:/src/trinitycore \
        mariadb:latest mysql -h"$SQL_HOST_ALIAS" -P3306 -uroot -p"$SQL_ROOT_PW" -e "
            CREATE DATABASE characters DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci ; 
            CREATE DATABASE world DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci ; 
        "
    # Import character and world schemas
    echo "Importing characters and world schemas..."
    docker run -it --rm \
        --network trinitycore_db_build_$VERSION \
        -v $LOCAL_SOURCE_DIR\:/src/trinitycore \
        mariadb:latest bash -c "
            cat /src/trinitycore/sql/base/characters_database.sql | mysql -h$SQL_HOST_ALIAS -P3306 -uroot -p$SQL_ROOT_PW -Dcharacters;
            cat /src/trinitycore/sql/base/world_database.sql | mysql -h$SQL_HOST_ALIAS -P3306 -uroot -p$SQL_ROOT_PW -Dworld;
        "
		
	if [ "$BRANCH" == "master" ] && [ ! -d $LOCAL_BUILD_DIR\db\realm\hotfix ]; then
		# Create hotfixes db
        echo "Creating hotfixes database..."
        docker run -it --rm \
            --network trinitycore_db_build_$VERSION \
            -v $LOCAL_SOURCE_DIR\:/src/trinitycore \
            mariadb:latest mysql -h"$SQL_HOST_ALIAS" -P3306 -uroot -p"$SQL_ROOT_PW" -e "
                CREATE DATABASE hotfixes DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci ; 
            "
        # Import hotfixes
        echo "Importing hotfixes schema..."
        docker run -it --rm \
            --network trinitycore_db_build_$VERSION \
            -v $LOCAL_SOURCE_DIR\:/src/trinitycore \
            mariadb:latest bash -c "
                cat /src/trinitycore/sql/base/hotfixes_database.sql | mysql -h$SQL_HOST_ALIAS -P3306 -uroot -p$SQL_ROOT_PW -Dhotfixes;
            "
	fi
	docker kill $db_container
fi
docker network rm trinitycore_db_build_$VERSION

# Git NUFAD for web-based administration
#docker run -it --rm \
#    -v $SCRIPTROOT\:/prepare \
#    trinitycore:universal bash -c "
#        mkdir -p /tmp;
#        cd /tmp;
#        git clone https://github.com/ggpwnkthx/nufad_installer.git;
#        mkdir -p /prepare/docker/nufad;
#        rsync -ah  --info=progress2 /tmp/nufad_installer/docker/nufad/ /prepare/docker/nufad;
#        mkdir -p /prepare/$BUILD_DIR/nufad;
#        git clone https://github.com/ggpwnkthx/nufad.git /prepare/$BUILD_DIR/nufad;
#    "
#docker build -t trinitycore:admin -f ./docker/nufad/Dockerfile ./docker/nufad/
