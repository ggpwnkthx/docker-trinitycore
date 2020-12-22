param (
    [string]$branch = "master",
    [string]$repo = "git://github.com/TrinityCore/TrinityCore.git"
)
if($branch -eq "master") {
    $version = "9.0.2"
} else {
    $version = $branch
}
$SQL_ROOT_PW = "trinity_root"

$SCRIPTROOT = "$PSScriptRoot/.."
$SOURCE_DIR = "source/$version"
$LOCAL_SOURCE_DIR = "$SCRIPTROOT\$SOURCE_DIR".Replace("/", "\")
$BUILD_DIR = "build/$version"
$LOCAL_BUILD_DIR = "$SCRIPTROOT\$BUILD_DIR".Replace("/", "\")
$CLIENT_DIR = "clients/$version"
$LOCAL_CLIENT_DIR = "$SCRIPTROOT\$CLIENT_DIR".Replace("/", "\")

# Build compiler container
echo "Building universal TrinityCore image..."
cd $SCRIPTROOT
docker build -t trinitycore:universal -f .\docker\Dockerfile_universal .\docker\

# Create directories
docker run -it --rm `
    -v $SCRIPTROOT\:/prepare `
    trinitycore:universal bash -c "
        mkdir -p /prepare/$SOURCE_DIR; 
        mkdir -p /prepare/$BUILD_DIR/bin; 
        mkdir -p /prepare/$BUILD_DIR/db/base;
    ".Replace("`r","")

# Download source code
docker run -it --rm `
    -v $LOCAL_SOURCE_DIR\:/src/trinitycore `
    trinitycore:universal bash -c "
        git clone -b $branch $repo /src/trinitycore;
        mkdir -p /src/trinitycore/build;
        cd /src/trinitycore; 
        git pull;
    ".Replace("`r","")
if($version -eq "3.3.5") {
    # Download Eluna
    docker run -it --rm `
        -v $LOCAL_SOURCE_DIR\:/src/trinitycore `
        trinitycore:universal bash -c "
            cd /src/trinitycore;
            git pull --recurse-submodules https://github.com/ElunaLuaEngine/ElunaTrinityWotlk.git;
            git submodule init;
            git submodule update;
            git remote add ElunaTrinityWotlk https://github.com/ElunaLuaEngine/ElunaTrinityWotlk.git;
        ".Replace("`r","")
}

# Build
docker run -it --rm `
    -v $LOCAL_SOURCE_DIR\:/src/trinitycore `
    -v $LOCAL_BUILD_DIR\:/opt/trinitycore `
    trinitycore:universal bash -c "
        cd /src/trinitycore/build; 
        cmake ../ \
            -DCMAKE_INSTALL_PREFIX=/opt/trinitycore \
            -DCONF_DIR=/opt/trinitycore/etc \
            -DLIBSDIR=/opt/trinitycore/lib \
            -DSCRIPTS=dynamic \
            -DWITH_WARNINGS=1;
        make -j `$(nproc);
        make install;
    ".Replace("`r","")

# Rename config files
docker run -it --rm `
    -v $SCRIPTROOT\:/prepare `
    trinitycore:universal bash -c "
        cp /prepare/$BUILD_DIR/etc/worldserver.conf.dist /prepare/$BUILD_DIR/etc/worldserver.conf;
        cp /prepare/$BUILD_DIR/etc/authserver.conf.dist /prepare/$BUILD_DIR/etc/authserver.conf;
        cp /prepare/$BUILD_DIR/etc/bnetserver.conf.dist /prepare/$BUILD_DIR/etc/bnetserver.conf;
    ".Replace("`r","")

# Get lastest releases of world database
$rel_ver = $version.Replace('.','')
$world_db = @(docker run -it --rm trinitycore:universal bash -c "curl -s https://api.github.com/repos/TrinityCore/TrinityCore/releases | grep browser_download_url | awk '{print `$2}' | grep TDB$rel_ver")[0]
docker run -it --rm `
    -v $LOCAL_SOURCE_DIR\:/src/trinitycore `
    -v $LOCAL_BUILD_DIR\:/opt/trinitycore `
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
    ".Replace("`r","")

# Extract maps from game client
if(!(Test-Path $LOCAL_BUILD_DIR\bin\data\mmaps))
{
    docker run -it --rm `
        -v $LOCAL_BUILD_DIR\:/opt/trinitycore `
        -v $LOCAL_CLIENT_DIR\:/opt/wow `
        trinitycore:universal bash -c "
            chmod +x /opt/trinitycore/bin/; 
            cd /opt/wow; 
            if [ ! -d /opt/wow/maps ]; then /opt/trinitycore/bin/mapextractor; fi;
            if [ ! -d /opt/wow/vmaps ]; then /opt/trinitycore/bin/vmap4extractor && mkdir /opt/wow/vmaps && /opt/trinitycore/bin/vmap4assembler Buildings vmaps; fi;
            if [ ! -d /opt/wow/mmaps ]; then mkdir /opt/wow/mmaps && /opt/trinitycore/bin/mmaps_generator; fi;
        ".Replace("`r","")
}

# Fix configuration files
docker run -it --rm `
    -v $LOCAL_BUILD_DIR\:/opt/trinitycore `
    trinitycore:universal bash -c "
        sed -i 's/^LoginDatabaseInfo.*`$/LoginDatabaseInfo  \= \`"auth_db;3306;root;$SQL_ROOT_PW;auth\`"/g' /opt/trinitycore/etc/*;
        sed -i 's/^WorldDatabaseInfo.*`$/WorldDatabaseInfo  \= \`"realm_db;3306;root;$SQL_ROOT_PW;world\`"/g' /opt/trinitycore/etc/*;
        sed -i 's/^CharacterDatabaseInfo.*`$/CharacterDatabaseInfo  \= \`"realm_db;3306;root;$SQL_ROOT_PW;characters\`"/g' /opt/trinitycore/etc/*;
        sed -i 's/^HotfixDatabaseInfo.*`$/HotfixDatabaseInfo  \= \`"realm_db;3306;root;$SQL_ROOT_PW;hotfixes\`"/g' /opt/trinitycore/etc/*;
        sed -i 's/^CMakeCommand.*`$/CMakeCommand  \= \\\`"\/use\/bin\/cmake\\\`"/g' /opt/trinitycore/etc/*;
        sed -i 's/^DataDir.*`$/DataDir  \= \\\`"\/opt\/trinitycore\/bin\/data\\\`"/g' /opt/trinitycore/etc/*;
        sed -i 's/^LogsDir.*`$/LogsDir  \= \\\`"\/opt\/trinitycore\/logs\\\`"/g' /opt/trinitycore/etc/*;
        sed -i 's/^SourceDirectory.*`$/SourceDirectory  \= \\\`"\/src\/trinitycore\\\`"/g' /opt/trinitycore/etc/*;
        sed -i 's/^BuildDirectory.*`$/BuildDirectory  \= \\\`"\/src\/trinitycore\/build\\\`"/g' /opt/trinitycore/etc/*;
        sed -i 's/^Console.Enable.*`$/Console.Enable \= 0/g' /opt/trinitycore/etc/*;
        sed -i 's/^Ra.Enable.*`$/Ra.Enable \= 1/g' /opt/trinitycore/etc/*;
        sed -i 's/^SOAP.Enable.*`$/SOAP.Enable \= 1/g' /opt/trinitycore/etc/*;
        sed -i 's/^SOAP.IP.*`$/SOAP.IP \= \\\`"0.0.0.0\\\`"/g' /opt/trinitycore/etc/*;
        sed -i 's/^Metric.Enable.*`$/Metric.Enable \= 1/g' /opt/trinitycore/etc/*;
        sed -i 's/^CertificatesFile.*`$/CertificatesFile \= \/opt\/trinitycore\/bin\/bnetserver.cert.pem/g' /opt/trinitycore/etc/*;
        sed -i 's/^PrivateKeyFile.*`$/PrivateKeyFile \= \/opt\/trinitycore\/bin\/bnetserver.key.pem/g' /opt/trinitycore/etc/*;
    ".Replace("`r","")

# Create docker network for database building
docker network create trinitycore_db_build_$version

# Start clean database server to get baseline binary SQL files
$sql_host_alias = "trinitycore_db"
if(!(Test-Path $LOCAL_BUILD_DIR\db\base\mysql))
{
    echo "Starting SQL service..."
    $db_container = (docker run -dP --rm `
        --network trinitycore_db_build_$version `
        --network-alias $sql_host_alias `
        -e "MYSQL_ROOT_PASSWORD=$SQL_ROOT_PW" `
        -v $LOCAL_BUILD_DIR\db\base:/var/lib/mysql `
        mariadb:latest --innodb-flush-method=O_DSYNC)
    # Wait for database to complete initilization
    echo "Waiting for SQL data to initialize..."
    docker run -it --rm `
        --network trinitycore_db_build_$version `
        mariadb:latest bash -c "
            while ! mysqladmin ping -h$sql_host_alias --silent; do sleep 1; done;
        ".Replace("`r","")
    docker kill $db_container
}
if(!(Test-Path $LOCAL_BUILD_DIR\db\auth\auth))
{
    # Copy baseline and build auth database on top
    echo "Copying initial SQL data for auth..."
    docker run -it --rm `
        -v $SCRIPTROOT\:/prepare `
        trinitycore:universal bash -c "
            mkdir -p /prepare/$BUILD_DIR/db/auth; 
            rsync -ah  --info=progress2 /prepare/$BUILD_DIR/db/base/ /prepare/$BUILD_DIR/db/auth;
        ".Replace("`r","")
    # Start auth database to get baseline auth binary SQL files
    echo "Starting auth SQL service..."
    $db_container = (docker run -dP --rm `
        --network trinitycore_db_build_$version `
        --network-alias $sql_host_alias `
        -v $LOCAL_BUILD_DIR\db\auth:/var/lib/mysql `
        mariadb:latest --innodb-flush-method=O_DSYNC)
    # Wait for database to complete initilization
    echo "Waiting for auth SQL to be ready..."
    docker run -it --rm `
        --network trinitycore_db_build_$version `
        -v $LOCAL_SOURCE_DIR\:/src/trinitycore `
        mariadb:latest bash -c "
            while ! mysqladmin ping -h$sql_host_alias --silent; do sleep 1; done;
        ".Replace("`r","")
    # Create auth db
    echo "Creating auth database..."
    docker run -it --rm `
        --network trinitycore_db_build_$version `
        -v $LOCAL_SOURCE_DIR\:/src/trinitycore `
        mariadb:latest mysql -h"$sql_host_alias" -P3306 -uroot -p"$SQL_ROOT_PW" -e "
            CREATE DATABASE auth DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci ; `
        ".Replace("`r","")
    # Import schema
    echo "Importing auth schema..."
    docker run -it --rm `
        --network trinitycore_db_build_$version `
        -v $LOCAL_SOURCE_DIR\:/src/trinitycore `
        mariadb:latest bash -c "
            cat /src/trinitycore/sql/base/auth_database.sql | mysql -h$sql_host_alias -P3306 -uroot -p$SQL_ROOT_PW -Dauth;
        ".Replace("`r","")
    # Add admin account
    echo "Adding admin account for RA service..."
    docker run -it --rm `
        --network trinitycore_db_build_$version `
        -v $LOCAL_SOURCE_DIR\:/src/trinitycore `
        mariadb:latest mysql -h"$sql_host_alias" -P3306 -uroot -p"$SQL_ROOT_PW" -Dauth -e "
            INSERT INTO account (id, username, sha_pass_hash) VALUES (1, 'ADMIN', '8301316D0D8448A34FA6D0C6BF1CBFA2B4A1A93A') ; `
            INSERT INTO account_access (id, gmlevel, RealmID) VALUES (1, 3, -1) ; `
        ".Replace("`r","")
    docker kill $db_container
}
if(!(Test-Path $LOCAL_BUILD_DIR\db\realm\world))
{
    # Copy baseline and build world and character databases on top
    echo "Copying initial SQL data for realms..."
    docker run -it --rm `
        -v $SCRIPTROOT\:/prepare `
        trinitycore:universal bash -c "
            mkdir -p /prepare/$BUILD_DIR/db/realm; 
            rsync -ah  --info=progress2 /prepare/$BUILD_DIR/db/base/ /prepare/$BUILD_DIR/db/realm;
        ".Replace("`r","")
    # Start realm database to get baseline auth binary SQL files
    echo "Starting realm SQL service..."
    $db_container = (docker run -dP --rm `
        --network trinitycore_db_build_$version `
        --network-alias $sql_host_alias `
        -v $LOCAL_BUILD_DIR\db\realm:/var/lib/mysql `
        mariadb:latest --innodb-flush-method=O_DSYNC)
    # Wait for database to complete initilization
    echo "Waiting for realm SQL to be ready..."
    docker run -it --rm `
        --network trinitycore_db_build_$version `
        -v $LOCAL_SOURCE_DIR\:/src/trinitycore `
        mariadb:latest bash -c "
            while ! mysqladmin ping -h$sql_host_alias --silent; do sleep 1; done;
        ".Replace("`r","")
    # Create character and world db
    echo "Creating characters and world databases..."
    docker run -it --rm `
        --network trinitycore_db_build_$version `
        -v $LOCAL_SOURCE_DIR\:/src/trinitycore `
        mariadb:latest mysql -h"$sql_host_alias" -P3306 -uroot -p"$SQL_ROOT_PW" -e "
            CREATE DATABASE characters DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci ; `
            CREATE DATABASE world DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci ; `
        ".Replace("`r","")
    # Import character and world schemas
    echo "Importing characters and world schemas..."
    docker run -it --rm `
        --network trinitycore_db_build_$version `
        -v $LOCAL_SOURCE_DIR\:/src/trinitycore `
        mariadb:latest bash -c "
            cat /src/trinitycore/sql/base/characters_database.sql | mysql -h$sql_host_alias -P3306 -uroot -p$SQL_ROOT_PW -Dcharacters;
            cat /src/trinitycore/sql/base/world_database.sql | mysql -h$sql_host_alias -P3306 -uroot -p$SQL_ROOT_PW -Dworld;
        ".Replace("`r","")

    if($branch -eq "master" -and !(Test-Path $LOCAL_BUILD_DIR\db\realm\hotfix))
    {
        # Create hotfixes db
        echo "Creating hotfixes database..."
        docker run -it --rm `
            --network trinitycore_db_build_$version `
            -v $LOCAL_SOURCE_DIR\:/src/trinitycore `
            mariadb:latest mysql -h"$sql_host_alias" -P3306 -uroot -p"$SQL_ROOT_PW" -e "
                CREATE DATABASE hotfixes DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci ; `
            ".Replace("`r","")
        # Import hotfixes
        echo "Importing hotfixes schema..."
        docker run -it --rm `
            --network trinitycore_db_build_$version `
            -v $LOCAL_SOURCE_DIR\:/src/trinitycore `
            mariadb:latest bash -c "
                cat /src/trinitycore/sql/base/hotfixes_database.sql | mysql -h$sql_host_alias -P3306 -uroot -p$SQL_ROOT_PW -Dhotfixes;
            ".Replace("`r","")
    }
    docker kill $db_container
}
docker network rm trinitycore_db_build_$version

# Git NUFAD for web-based administration
docker run -it --rm `
    -v $SCRIPTROOT\:/prepare `
    trinitycore:universal bash -c "
        mkdir -p /tmp;
        cd /tmp;
        git clone https://github.com/ggpwnkthx/nufad.git;
        mkdir -p /prepare/docker/nufad;
        rsync -ah  --info=progress2 /tmp/nufad/docker/nufad/ /prepare/docker/nufad;
        mkdir /prepare/$BUILD_DIR/nufad;
        rsync -ah  --info=progress2 /tmp/nufad/app/ /prepare/$BUILD_DIR/nufad;
    ".Replace("`r","")
docker build -t trinitycore:admin -f .\docker\nufad\Dockerfile .\docker\nufad\