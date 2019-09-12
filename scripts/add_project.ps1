param (
    [string]$project = "untitled",
    [string]$version = "8.2.0",
    [string]$realms = "Trinity",
    [bool]$development = $false
)

$SCRIPTROOT = "$PSScriptRoot/.."
$SOURCE_DIR = "source/$version"
$LOCAL_SOURCE_DIR = "$SCRIPTROOT\$SOURCE_DIR".Replace("/", "\")
$BUILD_DIR = "build/$version"
$LOCAL_BUILD_DIR = "$SCRIPTROOT\$BUILD_DIR".Replace("/", "\")
$CLIENT_DIR = "clients/$version"
$LOCAL_CLIENT_DIR = "$SCRIPTROOT\$CLIENT_DIR".Replace("/", "\")
$PROJECT_DIR = "projects/$project/$version"
$LOCAL_PROJECT_DIR = "$SCRIPTROOT\$PROJECT_DIR".Replace("/", "\")

$CONTAINER_PREFIX = "trinitycore_$project`_$version"

# Create directories and copy data if it doesnt already exist
echo "Copying binaries..."
$data = @("bin","lib")
foreach ($dir in $data) {
    if(!(Test-Path $LOCAL_PROJECT_DIR\server\$dir)) {
        docker run -it --rm `
            -v $SCRIPTROOT\:/prepare `
            trinitycore:universal bash -c "
                mkdir -p /prepare/$PROJECT_DIR/server/$dir
                rsync -ah --info=progress2 /prepare/$BUILD_DIR/$dir/ /prepare/$PROJECT_DIR/server/$dir
            ".Replace("`r","")
    }
}
# Copy the extracted and generated data to the realm directory
$data = @("dbc","maps","gt","vmaps","mmaps")
foreach ($dir in $data) {
    if((Test-Path $LOCAL_CLIENT_DIR\$dir) -and (!(Test-Path $LOCAL_PROJECT_DIR\server\bin\data\$dir))) {
        echo "Copying $dir data..."
        docker run -it --rm `
            -v $SCRIPTROOT\:/prepare `
            trinitycore:universal bash -c "
                mkdir -p /prepare/$PROJECT_DIR/server/bin/data/$dir
                rsync -ah --info=progress2 /prepare/$CLIENT_DIR/$dir/ /prepare/$PROJECT_DIR/server/bin/data/$dir
            ".Replace("`r","")
    }
}
if(!(Test-Path $LOCAL_PROJECT_DIR\auth\db)) {
    echo "Copying database for authserver..."
    docker run -it --rm `
        -v $SCRIPTROOT\:/prepare `
        trinitycore:universal bash -c "
            mkdir -p /prepare/$PROJECT_DIR/auth/db;
            rsync -ah --info=progress2 /prepare/$BUILD_DIR/db/auth/ /prepare/$PROJECT_DIR/auth/db;
            cp /prepare/$BUILD_DIR/etc/authserver.conf /prepare/$PROJECT_DIR/auth/authserver.conf;
            chmod 777 /prepare/$PROJECT_DIR/auth/authserver.conf;
            cp /prepare/$BUILD_DIR/etc/bnetserver.conf /prepare/$PROJECT_DIR/auth/bnetserver.conf;
            chmod 777 /prepare/$PROJECT_DIR/auth/bnetserver.conf;
            mkdir -p /prepare/$PROJECT_DIR/auth/logs;
        ".Replace("`r","")
}
docker network create $CONTAINER_PREFIX`_auth
foreach ($realm in $realms.Split(',')) {
    $REALM_DIR = "$PROJECT_DIR/realms/$realm"
    $LOCAL_REALM_DIR = "$SCRIPTROOT\$REALM_DIR".Replace("/", "\")
    docker network create $CONTAINER_PREFIX`_$realm
    echo "Copying realm databases..."
    if(!(Test-Path $LOCAL_REALM_DIR\db)) {
        docker run -it --rm `
            -v $SCRIPTROOT\:/prepare `
            trinitycore:universal bash -c "
                mkdir -p /prepare/$REALM_DIR/db;
                rsync -ah --info=progress2 /prepare/$BUILD_DIR/db/realm/ /prepare/$REALM_DIR/db;
                cp /prepare/$BUILD_DIR/etc/worldserver.conf /prepare/$REALM_DIR/worldserver.conf;
                chmod 777 /prepare/$REALM_DIR/worldserver.conf;
                mkdir -p /prepare/$REALM_DIR/logs;
            ".Replace("`r","")
    }
}
# Copy source data
echo "Copying any necessary source data..."
if($development) {
    echo "Copying source code..."
    docker run -it --rm `
        -v $SCRIPTROOT\:/prepare `
        trinitycore:universal bash -c "
            if [ ! -d $REALM_DIR/source/.git ]; then 
                rsync -ah --info=progress2 /prepare/$SOURCE_DIR/ $REALM_DIR/source; 
            fi;
    ".Replace("`r","")
}
if(!(Test-Path $LOCAL_PROJECT_DIR\source\sql)) {
    echo "Copying source SQL data..."
    docker run -it --rm `
        -v $SCRIPTROOT\:/prepare `
        trinitycore:universal bash -c "
            mkdir -p /prepare/$PROJECT_DIR/source/sql;
            rsync -ah --info=progress2 /prepare/$BUILD_DIR/sql/ /prepare/$PROJECT_DIR/source/sql;
        ".Replace("`r","")
}

# Add NUFAD Instance
if(!(Test-Path $LOCAL_PROJECT_DIR\admin)) {
    echo "Preparing admin interface..."
    docker run -it --rm `
        -v $SCRIPTROOT\:/prepare `
        trinitycore:universal bash -c "
            mkdir -p /prepare/$PROJECT_DIR/admin;
            rsync -ah  --info=progress2 /prepare/$BUILD_DIR/nufad/ /prepare/$PROJECT_DIR/admin;
        ".Replace("`r","")
    # Create SSL Certificate
    docker run -it --rm `
        -v $SCRIPTROOT\:/prepare `
        trinitycore:universal bash -c "
            mkdir -p /prepare/$PROJECT_DIR/admin/certs;
            openssl genrsa -out /prepare/$PROJECT_DIR/admin/certs/ssl.pass.key 2048;
            openssl rsa -in /prepare/$PROJECT_DIR/admin/certs/ssl.pass.key -out /prepare/$PROJECT_DIR/admin/certs/ssl.key;
            rm /prepare/$PROJECT_DIR/admin/certs/ssl.pass.key;
            openssl req -new -key /prepare/$PROJECT_DIR/admin/certs/ssl.key -out /prepare/$PROJECT_DIR/admin/certs/ssl.csr -subj `"/C=NA/ST=NA/`";
	        openssl x509 -req -days 7120 -in /prepare/$PROJECT_DIR/admin/certs/ssl.csr -signkey /prepare/$PROJECT_DIR/admin/certs/ssl.key -out /prepare/$PROJECT_DIR/admin/certs/ssl.crt;
        ".Replace("`r","")
}