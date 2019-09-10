param (
    [string]$project = "untitled",
    [string]$version = "8.2.0",
    [string]$realms = ""
)

$SOURCE_DIR = "source/$version"
$LOCAL_SOURCE_DIR = "$PSScriptRoot\$SOURCE_DIR".Replace("/", "\")
$BUILD_DIR = "build/$version"
$LOCAL_BUILD_DIR = "$PSScriptRoot\$BUILD_DIR".Replace("/", "\")
$CLIENT_DIR = "clients/$version"
$LOCAL_CLIENT_DIR = "$PSScriptRoot\$CLIENT_DIR".Replace("/", "\")
$PROJECT_DIR = "$project/$version"
$LOCAL_PROJECT_DIR = "$PSScriptRoot\projects\$PROJECT_DIR".Replace("/", "\")

$CONTAINER_PREFIX = "trinitycore_$project`_$version"

echo "Starting auth database..."
docker run -dP --rm `
    --name $CONTAINER_PREFIX`_auth_db `
    --network $CONTAINER_PREFIX`_auth `
    --network-alias auth_db `
    --expose 3306 `
    -v $LOCAL_PROJECT_DIR\auth\db:/var/lib/mysql `
    mariadb:latest --innodb-flush-method=O_DSYNC | Out-Null
echo "Waiting for auth database to be ready..."
docker run -it --rm `
    --network $CONTAINER_PREFIX`_auth `
    mariadb:latest bash -c "while ! mysqladmin ping -hauth_db --silent; do sleep 1; done" | Out-Null
echo "Starting auth server..."
switch($version) {
    "8.2.0" {
        $port_bnet = (docker run -it --rm `
            -v $LOCAL_PROJECT_DIR\auth\bnetserver.conf:/opt/trinitycore/etc/bnetserver.conf `
            trinitycore:universal bash -c "
                cat /opt/trinitycore/etc/bnetserver.conf | grep -e '^BattlenetPort' | awk '{print `$3}'
            ".Replace("`r",""))
        $port_rest = (docker run -it --rm `
            -v $LOCAL_PROJECT_DIR\auth\bnetserver.conf:/opt/trinitycore/etc/bnetserver.conf `
            trinitycore:universal bash -c "
                cat /opt/trinitycore/etc/bnetserver.conf | grep -e '^LoginREST\.Port' | awk '{print `$3}'
            ".Replace("`r",""))
        docker run -dP --rm `
            --name $CONTAINER_PREFIX`_auth `
            --network $CONTAINER_PREFIX`_auth `
            --network-alias auth `
            -p $port_bnet`:$port_bnet `
            -p $port_rest`:$port_rest `
            -v $LOCAL_PROJECT_DIR\server\bin:/opt/trinitycore/bin `
            -v $LOCAL_PROJECT_DIR\server\lib:/opt/trinitycore/lib `
            -v $LOCAL_PROJECT_DIR\auth\bnetserver.conf:/opt/trinitycore/etc/bnetserver.conf `
            -v $LOCAL_PROJECT_DIR\auth\logs:/opt/trinitycore/logs `
            trinitycore:universal bash -c "
                /opt/trinitycore/bin/bnetserver
            ".Replace("`r","") | Out-Null
        echo ""
        Write-Host "Bnetserver is running on port $port_bnet" -ForegroundColor Green -BackgroundColor Black
        echo ""
        break;
    }
    "3.3.5" {
        $port_auth = (docker run -it --rm `
            -v $LOCAL_PROJECT_DIR\auth\authserver.conf:/opt/trinitycore/etc/authserver.conf `
            trinitycore:universal bash -c "
                cat /opt/trinitycore/etc/authserver.conf | grep -e '^RealmServerPort' | awk '{print `$3}'
            ".Replace("`r",""))
        docker run -dP --rm `
            --name $CONTAINER_PREFIX`_auth `
            --network $CONTAINER_PREFIX`_auth `
            --network-alias auth `
            -p $port_auth`:$port_auth `
            -v $LOCAL_PROJECT_DIR\server\bin:/opt/trinitycore/bin `
            -v $LOCAL_PROJECT_DIR\server\lib:/opt/trinitycore/lib `
            -v $LOCAL_PROJECT_DIR\auth\authserver.conf:/opt/trinitycore/etc/authserver.conf `
            -v $LOCAL_PROJECT_DIR\auth\logs:/opt/trinitycore/logs `
            trinitycore:universal bash -c "
                /opt/trinitycore/bin/authserver
            ".Replace("`r","") | Out-Null
        echo ""
        Write-Host "Authserver is running on port $port_auth" -ForegroundColor Green -BackgroundColor Black
        echo ""
        break;
    }
}
if ($realms -eq "") {
    $realms = (Get-ChildItem -Directory -Path $LOCAL_PROJECT_DIR/realms | %{ echo $_.Name }) -Join(",")
}
foreach ($realm in $realms.Split(',')) {
    $LOCAL_REALM_DIR = "$LOCAL_PROJECT_DIR\realms\$realm"
    $realm_id=(docker run -it --rm `
        --network $CONTAINER_PREFIX`_auth `
        mariadb:latest mysql -hauth_db -P3306 -uroot -ptrinity_root -Dauth -N -e "
            SELECT id FROM realmlist WHERE name = '$realm';
        ".Replace("`r","")).replace("|","").trim()[1]
    if(!$realm_id) {
        docker run -it --rm `
            --network $CONTAINER_PREFIX`_auth `
            mariadb:latest mysql -hauth_db -P3306 -uroot -ptrinity_root -Dauth -N -e "
                INSERT INTO realmlist (name, flag, timezone) VALUES ('$realm', 0, 2);
            ".Replace("`r","") | Out-Null
        $realm_id=(docker run -it --rm `
            --network $CONTAINER_PREFIX`_auth `
            mariadb:latest mysql -hauth_db -P3306 -uroot -ptrinity_root -Dauth -N -e "
                SELECT id FROM realmlist WHERE name = '$realm';
            ".Replace("`r","")).replace("|","").trim()[1] | Out-Null
    }

    echo "Starting $realm realm database..."
    docker run -dP --rm `
        --name $CONTAINER_PREFIX`_$realm`_db `
        --network $CONTAINER_PREFIX`_$realm `
        --network-alias realm_db `
        -v $LOCAL_REALM_DIR\db:/var/lib/mysql `
        mariadb:latest --innodb-flush-method=O_DSYNC | Out-Null

    echo "Waiting for $realm realm database to be ready..."
    docker run -it --rm `
        --network $CONTAINER_PREFIX`_$realm `
        mariadb:latest bash -c "while ! mysqladmin ping -hrealm_db --silent; do sleep 1; done" | Out-Null

    echo "Configuring ports..."
    docker run -dP --rm `
        --name $CONTAINER_PREFIX`_portcheck `
        --expose 10000 `
        --expose 10001 `
        trinitycore:universal sleep 30 | Out-Null
    while(!$docker_inspect) { 
        $docker_inspect = (docker inspect $CONTAINER_PREFIX`_portcheck | ConvertFrom-Json)
    }
    $port_world = $docker_inspect.NetworkSettings.Ports.'10000/tcp'.HostPort
    $port_instance = $docker_inspect.NetworkSettings.Ports.'10001/tcp'.HostPort
    Remove-Variable docker_inspect | Out-Null
    docker kill $CONTAINER_PREFIX`_portcheck | Out-Null

    echo "Starting $realm realm server..."
    docker run -dP --rm `
        --name $CONTAINER_PREFIX`_$realm `
        --network $CONTAINER_PREFIX`_$realm `
        --network-alias $realm`_world `
        --expose 3443 `
        --expose 7878 `
        -p $port_world`:$port_world `
        -p $port_instance`:$port_instance `
        -v $LOCAL_PROJECT_DIR\server\bin:/opt/trinitycore/bin `
        -v $LOCAL_PROJECT_DIR\server\lib:/opt/trinitycore/lib `
        -v $LOCAL_PROJECT_DIR\source:/src/trinitycore `
        -v $LOCAL_REALM_DIR\worldserver.conf:/opt/trinitycore/temp/worldserver.conf `
        -v $LOCAL_REALM_DIR\logs:/opt/trinitycore/logs `
        trinitycore:universal bash -c "
            mkdir -p /opt/trinitycore/etc;
            cp /opt/trinitycore/temp/worldserver.conf /opt/trinitycore/etc/worldserver.conf;
            sed -i 's/^RealmID.*`$/RealmID \= $realm_id/g' /opt/trinitycore/etc/worldserver.conf;
            sed -i 's/^WorldServerPort.*`$/WorldServerPort \= $port_world/g' /opt/trinitycore/etc/worldserver.conf;
            sed -i 's/^InstanceServerPort.*`$/InstanceServerPort \= $port_instance/g' /opt/trinitycore/etc/worldserver.conf;
            sleep 5; 
            /opt/trinitycore/bin/worldserver
        ".Replace("`r","") | Out-Null
    echo "Connecting $realm realm server to auth network..."
    docker network connect $CONTAINER_PREFIX`_auth $CONTAINER_PREFIX`_$realm | Out-Null
    while(!$docker_inspect) { 
        $docker_inspect = (docker inspect $CONTAINER_PREFIX`_$realm | ConvertFrom-Json)
    }
    $port_ra = $docker_inspect.NetworkSettings.Ports.'3443/tcp'.HostPort
    echo ""
    Write-Host "Realm #$realm_id, $realm, is running on port $port_world" -Foreground Green -BackgroundColor Black
    Write-Host "    RA Telnet port is $port_ra" -Foreground Green -BackgroundColor Black
    echo ""
    docker run -it --rm `
        --network $CONTAINER_PREFIX`_auth `
        mariadb:latest mysql -hauth_db -P3306 -uroot -ptrinity_root -Dauth -N -e "
            UPDATE realmlist SET port = $port_world WHERE id = $realm_id;
        ".Replace("`r","")  | Out-Null
}
